import Foundation
import KuyuMLX
import KuyuTraining
import Synchronization
@testable import KuyuUI
import Testing

@MainActor
@Suite("Learning campaign execution controller")
struct LearningCampaignExecutionControllerTests {
    @Test(.timeLimit(.minutes(1)))
    func terminalSummaryIsAuthoritativeAfterEventStreamFinishes() async throws {
        let handle = ControlledTrainingRunHandle(runID: TrainingRunID("completed"))
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: handle))

        try start(controller, runID: handle.runID)
        await waitUntil { controller.hasActiveHandle && handle.waitCallCount == 1 }

        handle.emit(.started(makeManifest(runID: "completed")))
        handle.finishEvents()
        await Task.yield()

        #expect(controller.isRunning)
        #expect(controller.currentPhase == "started")

        let summary = makeSummary(runID: handle.runID, terminalState: .completed)
        handle.resolveWait(.success(summary))
        await waitUntil { !controller.isRunning }

        #expect(!controller.hasActiveHandle)
        #expect(controller.currentPhase == "completed")
        #expect(controller.progressFraction == 1)
        #expect(controller.terminalSummary == summary)
        #expect(handle.shutdownCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func reconnectAdoptsWorkerAndUsesTheNormalCompletionPath() async throws {
        let handle = ControlledTrainingRunHandle(runID: TrainingRunID("reconnected"))
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: handle))
        let artifactRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "reconnected-artifacts",
            isDirectory: true
        )

        let reconnected = try await controller.reconnect(artifactRoot: artifactRoot)

        #expect(reconnected)
        #expect(controller.hasActiveHandle)
        #expect(controller.isRunning)
        #expect(controller.activeRunID == handle.runID)
        #expect(controller.activeArtifactRoot == artifactRoot)
        #expect(controller.currentPhase == "reconnected")
        await waitUntil { handle.waitCallCount == 1 }

        let summary = makeSummary(runID: handle.runID, terminalState: .completed)
        handle.resolveWait(.success(summary))
        await waitUntil { !controller.isRunning }

        #expect(controller.terminalSummary == summary)
        #expect(handle.shutdownCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func waitFailureIsPreservedAsTheTerminalExecutionError() async throws {
        let handle = ControlledTrainingRunHandle(runID: TrainingRunID("failed"))
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: handle))

        try start(controller, runID: handle.runID)
        await waitUntil { controller.hasActiveHandle && handle.waitCallCount == 1 }
        handle.resolveWait(.failure(.failed("backend unavailable")))
        await waitUntil { !controller.isRunning }

        #expect(controller.currentPhase == "failed")
        #expect(controller.error == "backend unavailable")
        #expect(controller.readiness.status == .blocked)
        #expect(controller.terminalSummary == nil)
        #expect(handle.shutdownCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func restartIsRejectedUntilShutdownCompletes() async throws {
        let firstHandle = ControlledTrainingRunHandle(
            runID: TrainingRunID("first"),
            blocksShutdown: true
        )
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: firstHandle))

        try start(controller, runID: firstHandle.runID)
        await waitUntil { controller.hasActiveHandle }
        controller.stop()
        await waitUntil { firstHandle.shutdownCount == 1 }

        #expect(controller.isRunning)
        #expect(controller.currentPhase == "cancelling")
        #expect(throws: LearningCampaignExecutionError.alreadyRunning) {
            try start(controller, runID: TrainingRunID("blocked"))
        }

        firstHandle.resolveShutdown()
        await waitUntil { !controller.isRunning }

        let secondHandle = ControlledTrainingRunHandle(runID: TrainingRunID("second"))
        #expect(controller.replaceExecutor(ImmediateCampaignExecutor(handle: secondHandle)))
        try start(controller, runID: secondHandle.runID)
        await waitUntil { controller.hasActiveHandle }
        secondHandle.resolveWait(.success(makeSummary(
            runID: secondHandle.runID,
            terminalState: .completed
        )))
        await waitUntil { !controller.isRunning }
        #expect(controller.terminalSummary?.runID == secondHandle.runID)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledDelayedLaunchCannotOverwriteTheNextCampaign() async throws {
        let delayedHandle = ControlledTrainingRunHandle(runID: TrainingRunID("delayed"))
        let delayedExecutor = DelayedCampaignExecutor(handle: delayedHandle)
        let controller = makeController(executor: delayedExecutor)

        try start(controller, runID: delayedHandle.runID)
        await waitUntil { delayedExecutor.startCount == 1 }
        controller.stop()

        #expect(throws: LearningCampaignExecutionError.alreadyRunning) {
            try start(controller, runID: TrainingRunID("too-early"))
        }

        delayedExecutor.resolveLaunch()
        await waitUntil {
            delayedHandle.cancellationCount == 1
                && delayedHandle.shutdownCount == 1
                && !controller.isRunning
        }

        let nextHandle = ControlledTrainingRunHandle(runID: TrainingRunID("next"))
        #expect(controller.replaceExecutor(ImmediateCampaignExecutor(handle: nextHandle)))
        try start(controller, runID: nextHandle.runID)
        await waitUntil { controller.hasActiveHandle }

        #expect(controller.isRunning)
        #expect(controller.terminalSummary == nil)

        nextHandle.resolveWait(.success(makeSummary(
            runID: nextHandle.runID,
            terminalState: .completed
        )))
        await waitUntil { !controller.isRunning }
        #expect(controller.terminalSummary?.runID == nextHandle.runID)
    }

    @Test(.timeLimit(.minutes(1)))
    func persistedProgressCannotRegressNewerObservedProgress() {
        let handle = ControlledTrainingRunHandle(runID: TrainingRunID("progress"))
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: handle))
        controller.progressFraction = 0.8

        controller.synchronizePersistedState(LearningCampaignRunStoreState(
            artifactDirectory: FileManager.default.temporaryDirectory,
            plan: nil,
            status: nil,
            summary: nil,
            validation: nil,
            retention: nil,
            accelerator: nil,
            progressEvents: [],
            generations: [],
            candidates: [],
            vectorizedBatches: [],
            acceptedCheckpoints: []
        ))

        #expect(controller.progressFraction == 0.8)
    }

    @Test(.timeLimit(.minutes(1)))
    func persistedStateUpdatesTheVisiblePhaseWhileWorkerIsRunning() async throws {
        let handle = ControlledTrainingRunHandle(runID: TrainingRunID("persisted-phase"))
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: handle))
        try start(controller, runID: handle.runID)
        await waitUntil { controller.hasActiveHandle }
        let artifactRoot = try #require(controller.activeArtifactRoot)
        controller.synchronizePersistedState(LearningCampaignRunStoreState(
            artifactDirectory: artifactRoot,
            plan: nil,
            status: nil,
            summary: nil,
            validation: nil,
            retention: nil,
            accelerator: nil,
            progressEvents: [
                .init(
                    event: "generation-started",
                    timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                    phase: "generation",
                    generationIndex: 4,
                    message: "Generation 4 is running"
                )
            ],
            generations: [],
            candidates: [],
            vectorizedBatches: [],
            acceptedCheckpoints: []
        ))

        #expect(controller.currentPhase == "generation")
        #expect(controller.latestEvent == "Generation 4 is running")
        controller.stop()
        await waitUntil { !controller.isRunning }
    }

    @Test(.timeLimit(.minutes(1)))
    func persistedStateFromAnotherArtifactRootCannotAdvanceActiveRun() async throws {
        let handle = ControlledTrainingRunHandle(runID: TrainingRunID("active-root"))
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: handle))
        try start(controller, runID: handle.runID)
        await waitUntil { controller.hasActiveHandle }

        controller.synchronizePersistedState(LearningCampaignRunStoreState(
            artifactDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("different-campaign", isDirectory: true),
            plan: nil,
            status: LearningCampaignStatus(
                status: "completed",
                exitCode: 0,
                startedAt: "2026-07-15T00:00:00Z",
                finishedAt: "2026-07-15T00:01:00Z"
            ),
            summary: nil,
            validation: nil,
            retention: nil,
            accelerator: nil,
            progressEvents: [],
            generations: [],
            candidates: [],
            vectorizedBatches: [],
            acceptedCheckpoints: []
        ))

        #expect(controller.progressFraction == 0)
        controller.stop()
        await waitUntil { !controller.isRunning }
    }

    @Test(.timeLimit(.minutes(1)))
    func failedTerminalSummaryPreservesObservedProgress() async throws {
        let handle = ControlledTrainingRunHandle(runID: TrainingRunID("failed-progress"))
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: handle))
        try start(controller, runID: handle.runID)
        await waitUntil { controller.hasActiveHandle && handle.waitCallCount == 1 }
        controller.progressFraction = 0.4

        handle.resolveWait(.success(makeSummary(
            runID: handle.runID,
            terminalState: .failed,
            failureReasons: ["worker exited"]
        )))
        await waitUntil { !controller.isRunning }

        #expect(controller.currentPhase == "failed")
        #expect(controller.progressFraction == 0.4)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectedTerminalSummaryRepresentsCompletedSearch() async throws {
        let handle = ControlledTrainingRunHandle(runID: TrainingRunID("rejected-progress"))
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: handle))
        try start(controller, runID: handle.runID)
        await waitUntil { controller.hasActiveHandle && handle.waitCallCount == 1 }
        controller.progressFraction = 0.4

        handle.resolveWait(.success(makeSummary(
            runID: handle.runID,
            terminalState: .rejected,
            failureReasons: ["acceptance gate rejected checkpoint"]
        )))
        await waitUntil { !controller.isRunning }

        #expect(controller.currentPhase == "rejected")
        #expect(controller.progressFraction == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func stopDuringTerminalShutdownCannotReplaceSummaryWithCancellation() async throws {
        let handle = ControlledTrainingRunHandle(
            runID: TrainingRunID("terminal-shutdown"),
            blocksShutdown: true
        )
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: handle))
        try start(controller, runID: handle.runID)
        await waitUntil { controller.hasActiveHandle && handle.waitCallCount == 1 }

        let summary = makeSummary(runID: handle.runID, terminalState: .completed)
        handle.resolveWait(.success(summary))
        await waitUntil { handle.shutdownCount == 1 }
        controller.stop()

        #expect(controller.isRunning)
        #expect(controller.currentPhase == "finalizing")
        #expect(handle.cancellationCount == 0)

        handle.resolveShutdown()
        await waitUntil { !controller.isRunning }

        #expect(controller.terminalSummary == summary)
        #expect(controller.currentPhase == "completed")
    }

    @Test(.timeLimit(.minutes(1)))
    func failedExecutionRetainsPresentationAuthorityUntilCleared() async throws {
        let handle = ControlledTrainingRunHandle(runID: TrainingRunID("failed-authority"))
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: handle))
        try start(controller, runID: handle.runID)
        await waitUntil { controller.hasActiveHandle && handle.waitCallCount == 1 }
        handle.resolveWait(.failure(.failed("backend unavailable")))
        await waitUntil { !controller.isRunning }

        #expect(!controller.canAdoptPersistedPresentation)
        controller.clear()
        #expect(controller.canAdoptPersistedPresentation)
    }

    @Test(.timeLimit(.minutes(1)))
    func terminalOutcomeDoesNotDependOnEventStreamFinishing() async throws {
        let handle = ControlledTrainingRunHandle(
            runID: TrainingRunID("nonfinishing-events"),
            finishesEventsOnShutdown: false
        )
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: handle))
        try start(controller, runID: handle.runID)
        await waitUntil { controller.hasActiveHandle && handle.waitCallCount == 1 }

        let summary = makeSummary(runID: handle.runID, terminalState: .completed)
        handle.resolveWait(.success(summary))
        await waitUntil { !controller.isRunning }

        #expect(controller.terminalSummary == summary)
        #expect(controller.currentPhase == "completed")
    }

    @Test(.timeLimit(.minutes(1)))
    func shutdownDetachesWithoutCancellingTheActiveWorker() async throws {
        let handle = ControlledTrainingRunHandle(runID: TrainingRunID("detached-active"))
        let controller = makeController(executor: ImmediateCampaignExecutor(handle: handle))
        try start(controller, runID: handle.runID)
        await waitUntil { controller.hasActiveHandle && handle.waitCallCount == 1 }

        await controller.shutdown()

        #expect(!controller.isRunning)
        #expect(!controller.hasActiveHandle)
        #expect(controller.currentPhase == "detached")
        #expect(handle.detachmentCount == 1)
        #expect(handle.cancellationCount == 0)
        #expect(handle.shutdownCount == 0)

        handle.resolveWait(.success(makeSummary(
            runID: handle.runID,
            terminalState: .completed
        )))
    }

    @Test(.timeLimit(.minutes(1)))
    func shutdownDuringLaunchDetachesTheWorkerAfterLaunchCompletes() async throws {
        let handle = ControlledTrainingRunHandle(runID: TrainingRunID("detached-launch"))
        let executor = DelayedCampaignExecutor(handle: handle)
        let controller = makeController(executor: executor)
        try start(controller, runID: handle.runID)
        await waitUntil { executor.startCount == 1 }

        await controller.shutdown()
        executor.resolveLaunch()
        await waitUntil { handle.detachmentCount == 1 }

        #expect(handle.cancellationCount == 0)
        #expect(handle.shutdownCount == 0)
        #expect(controller.currentPhase == "detached")
    }

    private func makeController(
        executor: any LearningCampaignRunCommanding
    ) -> LearningCampaignExecutionController {
        LearningCampaignExecutionController(
            executor: executor,
            logStore: UILogStore(buffer: UILogBuffer())
        )
    }

    private func start(
        _ controller: LearningCampaignExecutionController,
        runID: TrainingRunID
    ) throws {
        try controller.start(
            request: makeRequest(runID: runID),
            continuationArtifactRoot: nil,
            initialLogRecord: LearningCampaignRunLogRecord(
                category: .lifecycle,
                phase: "starting",
                title: "Campaign launch requested"
            ),
            context: LearningCampaignExecutionContext(
                taskID: "lift",
                suiteCount: 1,
                episodesPerSuite: 1
            )
        )
    }

    private func makeRequest(runID: TrainingRunID) -> TrainingRunRequest {
        TrainingRunRequest(
            runID: runID,
            artifactRoot: FileManager.default.temporaryDirectory
                .appendingPathComponent("campaign-controller-\(runID)", isDirectory: true),
            taskProfileID: "lift-v1",
            policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
            actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
            populationSize: 2,
            generationLimit: 1
        )
    }

    private func makeManifest(runID: String) -> LearningRunManifest {
        LearningRunManifest(
            runID: runID,
            mode: .rlRollout,
            configHash: "config",
            suiteID: "6",
            seedSet: [1],
            policyID: "policy",
            workerCount: 1,
            startedAt: Date(),
            terminalState: .running
        )
    }

    private func makeSummary(
        runID: TrainingRunID,
        terminalState: TrainingRunTerminalState,
        failureReasons: [String] = []
    ) -> TrainingRunSummary {
        TrainingRunSummary(
            runID: runID,
            artifactRoot: FileManager.default.temporaryDirectory,
            terminalState: terminalState,
            generationCount: 1,
            candidateCount: 2,
            failureReasons: failureReasons
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
        #expect(condition())
    }
}

@MainActor
private final class DelayedCampaignExecutor: LearningCampaignRunCommanding {
    private let handle: ControlledTrainingRunHandle
    private var continuation: CheckedContinuation<ControlledTrainingRunHandle, Never>?
    private(set) var startCount = 0

    init(handle: ControlledTrainingRunHandle) {
        self.handle = handle
    }

    func startTrainingRun(request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        startCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resumeTrainingRun(request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        handle
    }

    func resolveLaunch() {
        continuation?.resume(returning: handle)
        continuation = nil
    }
}

@MainActor
private final class ImmediateCampaignExecutor: LearningCampaignRunCommanding {
    private let handle: ControlledTrainingRunHandle

    init(handle: ControlledTrainingRunHandle) {
        self.handle = handle
    }

    func startTrainingRun(request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        handle
    }

    func resumeTrainingRun(request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        handle
    }

    func reconnectTrainingRun(artifactRoot: URL) async throws -> (any TrainingRunHandle)? {
        handle
    }
}

private final class ControlledTrainingRunHandle: TrainingRunHandle, Sendable {
    enum Failure: Error, Sendable {
        case cancelled
        case failed(String)

        var description: String {
            switch self {
            case .cancelled:
                return "cancelled"
            case .failed(let message):
                return message
            }
        }
    }

    enum WaitOutcome: Sendable {
        case success(TrainingRunSummary)
        case failure(Failure)
    }

    private struct State: Sendable {
        let eventContinuation: AsyncStream<TrainingRunEvent>.Continuation
        let blocksShutdown: Bool
        let finishesEventsOnShutdown: Bool
        var waitContinuation: CheckedContinuation<TrainingRunSummary, any Error>?
        var pendingWaitOutcome: WaitOutcome?
        var shutdownContinuation: CheckedContinuation<Void, Never>?
        var shutdownReleased: Bool
        var waitCallCount = 0
        var cancellationCount = 0
        var detachmentCount = 0
        var shutdownCount = 0
    }

    let runID: TrainingRunID
    let progress = Progress(totalUnitCount: 1)
    let events: AsyncStream<TrainingRunEvent>
    private let state: Mutex<State>

    var waitCallCount: Int {
        state.withLock { $0.waitCallCount }
    }

    var cancellationCount: Int {
        state.withLock { $0.cancellationCount }
    }

    var shutdownCount: Int {
        state.withLock { $0.shutdownCount }
    }

    var detachmentCount: Int {
        state.withLock { $0.detachmentCount }
    }

    init(
        runID: TrainingRunID,
        blocksShutdown: Bool = false,
        finishesEventsOnShutdown: Bool = true
    ) {
        self.runID = runID
        let pair = AsyncStream<TrainingRunEvent>.makeStream()
        self.events = pair.stream
        self.state = Mutex(State(
            eventContinuation: pair.continuation,
            blocksShutdown: blocksShutdown,
            finishesEventsOnShutdown: finishesEventsOnShutdown,
            shutdownReleased: !blocksShutdown
        ))
    }

    func emit(_ event: TrainingRunEvent) {
        let continuation = state.withLock { $0.eventContinuation }
        continuation.yield(event)
    }

    func finishEvents() {
        let continuation = state.withLock { $0.eventContinuation }
        continuation.finish()
    }

    func cancel() {
        let continuation = state.withLock { state in
            state.cancellationCount += 1
            return state.eventContinuation
        }
        continuation.finish()
        resolveWait(.failure(.cancelled))
    }

    func wait() async throws -> TrainingRunSummary {
        try await withCheckedThrowingContinuation { continuation in
            let pendingOutcome = state.withLock { state -> WaitOutcome? in
                state.waitCallCount += 1
                if let outcome = state.pendingWaitOutcome {
                    state.pendingWaitOutcome = nil
                    return outcome
                }
                state.waitContinuation = continuation
                return nil
            }
            if let pendingOutcome {
                resume(continuation, with: pendingOutcome)
            }
        }
    }

    func detach() async {
        state.withLock { $0.detachmentCount += 1 }
    }

    func shutdown() async {
        let eventContinuation = state.withLock { state -> AsyncStream<TrainingRunEvent>.Continuation? in
            state.shutdownCount += 1
            return state.finishesEventsOnShutdown ? state.eventContinuation : nil
        }
        eventContinuation?.finish()
        let shouldBlock = state.withLock { state in
            state.blocksShutdown && !state.shutdownReleased
        }
        guard shouldBlock else { return }
        await withCheckedContinuation { continuation in
            let resumeImmediately = state.withLock { state -> Bool in
                if state.shutdownReleased {
                    return true
                }
                state.shutdownContinuation = continuation
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func resolveWait(_ outcome: WaitOutcome) {
        let continuation = state.withLock { state -> CheckedContinuation<TrainingRunSummary, any Error>? in
            guard let continuation = state.waitContinuation else {
                if state.pendingWaitOutcome == nil {
                    state.pendingWaitOutcome = outcome
                }
                return nil
            }
            state.waitContinuation = nil
            return continuation
        }
        if let continuation {
            resume(continuation, with: outcome)
        }
    }

    func resolveShutdown() {
        let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.shutdownReleased = true
            let continuation = state.shutdownContinuation
            state.shutdownContinuation = nil
            return continuation
        }
        continuation?.resume()
    }

    private func resume(
        _ continuation: CheckedContinuation<TrainingRunSummary, any Error>,
        with outcome: WaitOutcome
    ) {
        switch outcome {
        case .success(let summary):
            continuation.resume(returning: summary)
        case .failure(let failure):
            continuation.resume(throwing: TestFailure(message: failure.description))
        }
    }
}

private struct TestFailure: Error, Sendable, CustomStringConvertible {
    let message: String
    var description: String { message }
}
