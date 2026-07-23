import Foundation
import KuyuTraining
@testable import KuyuWorkerRuntime
import Testing

@Suite("Training worker runtime")
struct TrainingWorkerRuntimeTests {
    @Test(.timeLimit(.minutes(1)))
    func invocationParserPreservesRepeatedAuthorizedRoots() throws {
        let launchID = UUID()
        let invocation = try ManasMLXTrainingWorkerInvocation.parse(
            commandLineArguments: [
                ManasMLXTrainingWorkerInvocation.commandName,
                "--launch-root", "/tmp/worker-launches",
                "--launch-id", launchID.uuidString,
                "--launch-digest", String(repeating: "a", count: 64),
                "--allowed-artifact-root", "/tmp/artifacts-a",
                "--allowed-artifact-root", "/tmp/artifacts-b",
                "--allowed-source-root", "/tmp/sources",
            ]
        )

        #expect(invocation.launchID == launchID)
        #expect(invocation.allowedArtifactRoots.map(\.path) == [
            "/tmp/artifacts-a",
            "/tmp/artifacts-b",
        ])
        #expect(invocation.allowedSourceRoots.map(\.path) == ["/tmp/sources"])
    }

    @Test(.timeLimit(.minutes(1)))
    func invocationParserRejectsUnknownOptions() {
        #expect(
            throws: ManasMLXTrainingWorkerInvocation.InvocationError
                .unknownOption("--untrusted-root")
        ) {
            _ = try ManasMLXTrainingWorkerInvocation.parse(
                commandLineArguments: [
                    ManasMLXTrainingWorkerInvocation.commandName,
                    "--untrusted-root", "/tmp",
                ]
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func serviceHonorsStopRequestedBeforeExecutionAndReleasesOwnership() async throws {
        let fixture = try workerFixture("worker-runtime")
        let control = WorkerRuntimeControl()
        let stopRequest = TrainingRunWorkerStopRequest(
            artifactRoot: fixture.artifactRoot,
            launchID: fixture.launch.launchID,
            attemptID: fixture.launch.attemptID
        )
        try stopRequest.request()
        let outcome = try await ManasMLXTrainingWorkerService(
            executor: WorkerRuntimeControlledExecutor(
                runID: fixture.runID,
                artifactRoot: fixture.artifactRoot,
                control: control
            )
        ).execute(fixture.invocation)

        #expect(outcome.runID == fixture.runID.rawValue)
        #expect(outcome.terminalState == .cancelled)
        #expect(outcome.generationCount == 0)
        #expect(!(await control.didStart()))
        #expect(FileManager.default.fileExists(atPath: stopRequest.sentinelURL.path))
        let identity = TrainingRunWorkerAttemptIdentity(
            launchID: fixture.launch.launchID,
            attemptID: fixture.launch.attemptID,
            launchSHA256Digest: fixture.receipt.sha256Digest
        )
        let persisted = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
            in: fixture.artifactRoot,
            expectedRunID: fixture.runID,
            expectedWorkerAttemptIdentity: identity
        )
        #expect(persisted.summary.terminalState == .cancelled)
        let ownershipKey = TrainingRunWorkerLease.ownershipKey(for: fixture.artifactRoot)
        let metadataURL = fixture.launchRoot
            .appendingPathComponent(
                TrainingRunWorkerLease.ownershipDirectoryName,
                isDirectory: true
            )
            .appendingPathComponent("\(ownershipKey).json", isDirectory: false)
        #expect(!FileManager.default.fileExists(atPath: metadataURL.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func stopRequestedAfterLeasePublicationCancelsCurrentAttempt() async throws {
        let fixture = try workerFixture("worker-runtime-stop-race")
        let control = WorkerRuntimeControl()
        let executionTask = Task {
            try await ManasMLXTrainingWorkerService(
                executor: WorkerRuntimeControlledExecutor(
                    runID: fixture.runID,
                    artifactRoot: fixture.artifactRoot,
                    control: control
                )
            ).execute(fixture.invocation)
        }
        await control.waitUntilStarted()
        let stopRequest = TrainingRunWorkerStopRequest(
            artifactRoot: fixture.artifactRoot,
            launchID: fixture.launch.launchID,
            attemptID: fixture.launch.attemptID
        )

        try stopRequest.request()

        let cancelledOutcome = try await executionTask.value
        #expect(cancelledOutcome.terminalState == .cancelled)
        #expect(cancelledOutcome.processDisposition == .cancellation)
        #expect(try stopRequest.isRequested())
        let identity = TrainingRunWorkerAttemptIdentity(
            launchID: fixture.launch.launchID,
            attemptID: fixture.launch.attemptID,
            launchSHA256Digest: fixture.receipt.sha256Digest
        )
        let outcome = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
            in: fixture.artifactRoot,
            expectedRunID: fixture.runID,
            expectedWorkerAttemptIdentity: identity
        )
        #expect(outcome.summary.terminalState == .cancelled)
        let progressRoot = TrainingRunWorkerLaunchArtifactStore(
            rootDirectory: fixture.launchRoot
        ).launchDirectory(for: fixture.launch.launchID)
        let progress = try #require(
            try TrainingRunWorkerProgressStore().artifact(
                in: progressRoot,
                expectedWorkerAttemptIdentity: identity
            )
        )
        #expect(progress.event.event == "controlled-start")
    }

    @Test(.timeLimit(.minutes(1)))
    func progressRecorderInitializationFailureReleasesOwnership() async throws {
        let fixture = try workerFixture("worker-runtime-progress-init")
        let progressRoot = TrainingRunWorkerLaunchArtifactStore(
            rootDirectory: fixture.launchRoot
        ).launchDirectory(for: fixture.launch.launchID)
        let progressDirectory = progressRoot.appendingPathComponent(
            TrainingRunWorkerProgressArtifact.directoryName,
            isDirectory: true
        )
        let externalDirectory = fixture.artifactRoot.deletingLastPathComponent()
            .appendingPathComponent("external-progress", isDirectory: true)
        try FileManager.default.createDirectory(
            at: externalDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: progressDirectory,
            withDestinationURL: externalDirectory
        )

        await #expect(throws: TrainingRunWorkerProgressStore.StoreError.self) {
            _ = try await ManasMLXTrainingWorkerService(
                executor: WorkerRuntimeStaticExecutor(
                    summary: TrainingRunSummary(
                        runID: fixture.runID,
                        artifactRoot: fixture.artifactRoot,
                        terminalState: .completed
                    )
                )
            ).execute(fixture.invocation)
        }

        let canonicalArtifactRoot = fixture.artifactRoot.standardizedFileURL
            .resolvingSymlinksInPath()
        let ownershipKey = TrainingRunWorkerLease.ownershipKey(for: canonicalArtifactRoot)
        let metadataURL = fixture.launchRoot
            .appendingPathComponent(
                TrainingRunWorkerLease.ownershipDirectoryName,
                isDirectory: true
            )
            .appendingPathComponent("\(ownershipKey).json", isDirectory: false)
        #expect(!FileManager.default.fileExists(atPath: metadataURL.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func servicePersistsFailureWhenExecutorCompletesWithoutAcceptedCheckpoint() async throws {
        let fixture = try workerFixture("worker-runtime-invalid-success")
        let outcome = try await ManasMLXTrainingWorkerService(
            executor: WorkerRuntimeStaticExecutor(
                summary: TrainingRunSummary(
                    runID: fixture.runID,
                    artifactRoot: fixture.artifactRoot,
                    terminalState: .completed,
                    generationCount: 3,
                    candidateCount: 12
                )
            )
        ).execute(fixture.invocation)

        #expect(outcome.terminalState == .failed)
        #expect(outcome.processDisposition == .failure)
        #expect(outcome.generationCount == 3)
        #expect(outcome.candidateCount == 12)
        #expect(
            outcome.failureReasons.contains(
                "training worker completed without an accepted checkpoint"
            )
        )
        let identity = TrainingRunWorkerAttemptIdentity(
            launchID: fixture.launch.launchID,
            attemptID: fixture.launch.attemptID,
            launchSHA256Digest: fixture.receipt.sha256Digest
        )
        let persisted = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
            in: fixture.artifactRoot,
            expectedRunID: fixture.runID,
            expectedWorkerAttemptIdentity: identity
        )
        #expect(persisted.summary == TrainingRunSummary(
            runID: fixture.runID,
            artifactRoot: fixture.artifactRoot,
            terminalState: .failed,
            generationCount: 3,
            candidateCount: 12,
            failureReasons: ["training worker completed without an accepted checkpoint"]
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func serviceExecutesAgainstArtifactOwnedSourceSnapshot() async throws {
        let fixture = try workerFixture("worker-runtime-durable-source")
        let recorder = WorkerRuntimeRequestRecorder()
        let outcome = try await ManasMLXTrainingWorkerService(
            executor: WorkerRuntimeRecordingExecutor(
                summary: TrainingRunSummary(
                    runID: fixture.runID,
                    artifactRoot: fixture.artifactRoot,
                    terminalState: .rejected,
                    failureReasons: ["candidate-rejected"]
                ),
                recorder: recorder
            )
        ).execute(fixture.invocation)

        #expect(outcome.terminalState == .rejected)
        let sourceBundle = await recorder.sourceBundle()
        let recordedSource = try #require(sourceBundle)
        let expectedSource = fixture.artifactRoot
            .appendingPathComponent(
                TrainingRunWorkerSourceSnapshotStore.continuationDirectoryName,
                isDirectory: true
            )
            .appendingPathComponent(
                TrainingRunWorkerSourceSnapshotStore.snapshotDirectoryName,
                isDirectory: true
            )
        #expect(recordedSource.url == expectedSource)
        #expect(
            try Data(contentsOf: expectedSource.appendingPathComponent("model.json"))
                == Data("model".utf8)
        )
        try TrainingRunWorkerSourceIntegrityVerifier(
            allowedSourceRoots: [fixture.artifactRoot]
        ).verify(
            TrainingRunWorkerLaunchArtifact(
                launchID: fixture.launch.launchID,
                attemptID: fixture.launch.attemptID,
                createdAt: fixture.launch.createdAt,
                operation: .start(
                    TrainingRunRequest(
                        runID: fixture.runID,
                        artifactRoot: fixture.artifactRoot,
                        taskProfileID: "lift",
                        policyContract: ReferenceQuadrotorLearningContracts
                            .temporalCTBRPolicyContract(),
                        actionContract: ReferenceQuadrotorLearningContracts
                            .bodyRateActionContract(),
                        sourceBundle: recordedSource
                    )
                )
            )
        )
    }

    private func temporaryDirectory(_ label: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func workerFixture(_ label: String) throws -> WorkerRuntimeFixture {
        let root = try temporaryDirectory(label)
        let launchRoot = root.appendingPathComponent("launches", isDirectory: true)
        let artifactParent = root.appendingPathComponent("artifacts", isDirectory: true)
        let artifactRoot = artifactParent.appendingPathComponent("run", isDirectory: true)
        let sourceParent = root.appendingPathComponent("sources", isDirectory: true)
        let sourceRoot = sourceParent.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try Data("model".utf8).write(
            to: sourceRoot.appendingPathComponent("model.json", isDirectory: false)
        )
        let sourceReference = try TrainingRunWorkerSourceIntegrityVerifier(
            allowedSourceRoots: [sourceParent]
        ).pinnedReference(
            ModelBundleReference(
                bundleID: "worker-runtime-source",
                kind: .source,
                url: sourceRoot
            )
        )
        let runID = TrainingRunID("\(label)-run")
        let launch = TrainingRunWorkerLaunchArtifact(
            operation: .start(
                TrainingRunRequest(
                    runID: runID,
                    artifactRoot: artifactRoot,
                    taskProfileID: "lift",
                    policyContract: ReferenceQuadrotorLearningContracts
                        .temporalCTBRPolicyContract(),
                    actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
                    sourceBundle: sourceReference
                )
            )
        )
        let receipt = try TrainingRunWorkerLaunchArtifactStore(rootDirectory: launchRoot)
            .write(launch)
        let invocation = try ManasMLXTrainingWorkerInvocation(
            launchRoot: launchRoot,
            launchID: launch.launchID,
            launchDigest: receipt.sha256Digest,
            allowedArtifactRoots: [artifactParent],
            allowedSourceRoots: [sourceParent]
        )
        return WorkerRuntimeFixture(
            launchRoot: launchRoot,
            artifactRoot: artifactRoot,
            runID: runID,
            launch: launch,
            receipt: receipt,
            invocation: invocation
        )
    }
}

private struct WorkerRuntimeFixture {
    let launchRoot: URL
    let artifactRoot: URL
    let runID: TrainingRunID
    let launch: TrainingRunWorkerLaunchArtifact
    let receipt: TrainingRunWorkerLaunchArtifactStore.Receipt
    let invocation: ManasMLXTrainingWorkerInvocation
}

private actor WorkerRuntimeControl {
    private var started = false
    private var cancelled = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<TrainingRunSummary, Error>?

    func markStarted() {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func didStart() -> Bool {
        started
    }

    func wait() async throws -> TrainingRunSummary {
        if cancelled { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation
        }
    }

    func cancel() {
        cancelled = true
        completion?.resume(throwing: CancellationError())
        completion = nil
    }
}

private struct WorkerRuntimeControlledExecutor: AnyTrainingRunExecuting {
    let runID: TrainingRunID
    let artifactRoot: URL
    let control: WorkerRuntimeControl

    func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        await control.markStarted()
        return WorkerRuntimeControlledHandle(
            runID: runID,
            artifactRoot: artifactRoot,
            control: control
        )
    }

    func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        try await start(
            TrainingRunRequest(
                runID: request.runID,
                artifactRoot: request.destinationArtifactRoot,
                taskProfileID: request.taskProfileID,
                policyContract: request.policyContract,
                actionContract: request.actionContract
            )
        )
    }

    func continuationSelection(from artifactRoot: URL) throws -> TrainingContinuationSelection {
        throw WorkerRuntimeTestError.unsupported
    }

    func validate(_ request: TrainingRunRequest) throws {}
    func validate(_ request: TrainingResumeRequest) throws {}
}

private final class WorkerRuntimeControlledHandle: TrainingRunHandle, Sendable {
    let runID: TrainingRunID
    let progress = Progress(totalUnitCount: 1)
    let events: AsyncStream<TrainingRunEvent>
    private let artifactRoot: URL
    private let control: WorkerRuntimeControl
    private let eventContinuation: AsyncStream<TrainingRunEvent>.Continuation

    init(runID: TrainingRunID, artifactRoot: URL, control: WorkerRuntimeControl) {
        let eventPipe = AsyncStream<TrainingRunEvent>.makeStream()
        self.runID = runID
        self.events = eventPipe.stream
        self.artifactRoot = artifactRoot
        self.control = control
        self.eventContinuation = eventPipe.continuation
        eventPipe.continuation.yield(
            .progress(TrainingRunProgressEvent(event: "controlled-start"))
        )
    }

    func cancel() {
        Task { await control.cancel() }
    }

    func wait() async throws -> TrainingRunSummary {
        try await control.wait()
    }

    func shutdown() async {
        eventContinuation.finish()
    }
}

private struct WorkerRuntimeStaticExecutor: AnyTrainingRunExecuting {
    let summary: TrainingRunSummary

    func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        WorkerRuntimeStaticHandle(summary: summary)
    }

    func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        WorkerRuntimeStaticHandle(summary: summary)
    }

    func continuationSelection(from artifactRoot: URL) throws -> TrainingContinuationSelection {
        throw WorkerRuntimeTestError.unsupported
    }

    func validate(_ request: TrainingRunRequest) throws {}

    func validate(_ request: TrainingResumeRequest) throws {}
}

private actor WorkerRuntimeRequestRecorder {
    private var recordedSourceBundle: ModelBundleReference?

    func record(_ request: TrainingRunRequest) {
        recordedSourceBundle = request.sourceBundle
    }

    func sourceBundle() -> ModelBundleReference? {
        recordedSourceBundle
    }
}

private struct WorkerRuntimeRecordingExecutor: AnyTrainingRunExecuting {
    let summary: TrainingRunSummary
    let recorder: WorkerRuntimeRequestRecorder

    func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        await recorder.record(request)
        return WorkerRuntimeStaticHandle(summary: summary)
    }

    func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        throw WorkerRuntimeTestError.unsupported
    }

    func continuationSelection(from artifactRoot: URL) throws -> TrainingContinuationSelection {
        throw WorkerRuntimeTestError.unsupported
    }

    func validate(_ request: TrainingRunRequest) throws {}
    func validate(_ request: TrainingResumeRequest) throws {}
}

private final class WorkerRuntimeStaticHandle: TrainingRunHandle, Sendable {
    let runID: TrainingRunID
    let progress = Progress(totalUnitCount: 1)
    let events = AsyncStream<TrainingRunEvent> { continuation in
        continuation.finish()
    }
    private let summary: TrainingRunSummary

    init(summary: TrainingRunSummary) {
        self.runID = summary.runID
        self.summary = summary
    }

    func cancel() {}

    func wait() async throws -> TrainingRunSummary {
        summary
    }

    func shutdown() async {}
}

private enum WorkerRuntimeTestError: Error {
    case unsupported
}
