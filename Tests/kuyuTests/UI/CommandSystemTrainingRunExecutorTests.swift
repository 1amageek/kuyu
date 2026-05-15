import Foundation
import KuyuMLX
import KuyuTraining
@testable import KuyuUI
import Testing

@MainActor
@Test(.timeLimit(.minutes(1))) func commandSystemUsesInjectedTrainingRunExecutor() async throws {
    let runID = TrainingRunID("injected-training-run")
    let progressEvent = TrainingRunProgressEvent(
        event: "candidate-evaluated",
        phase: "candidate",
        seed: "seed-1",
        generationIndex: 2,
        candidateID: "g2-c99",
        progressFraction: 0.25,
        fitness: -10,
        rewardAverage: -2,
        taskPassRate: 0.5,
        safetyViolationRate: 0,
        holdTimeRatio: 0.5,
        altitudeErrorRatio: 0.2,
        workerThroughput: 20,
        gpuAcceleration: true,
        tensorWorldBatch: true,
        tensorSummary: true,
        vectorizedPopulationSize: 100,
        vectorizedWorldCount: 100,
        vectorizedHistoryLength: 32,
        vectorizedObservationDimension: 64,
        vectorizedActionDimension: 4,
        message: "Candidate evaluated"
    )
    let commandSystem = CommandSystem(
        modelStore: ManasMLXModelStore(),
        trainingRunExecutor: StaticTrainingRunExecutor(runID: runID, event: progressEvent)
    )
    let result = try await commandSystem.startTrainingRun(request: TrainingRunRequest(
        runID: runID,
        artifactRoot: FileManager.default.temporaryDirectory
            .appendingPathComponent("command-system-injected-\(UUID().uuidString)", isDirectory: true),
        taskProfileID: "lift",
        policyContract: .referenceQuadrotorTemporalCTBR(),
        populationSize: 100,
        generationLimit: 1
    ))

    var progressEvents: [TrainingRunProgressEvent] = []
    for await event in result.events {
        if case .progress(let progressEvent) = event {
            progressEvents.append(progressEvent)
        }
    }

    #expect(progressEvents.count == 1)
    #expect(progressEvents.first?.candidateID == "g2-c99")
    #expect(progressEvents.first?.gpuAcceleration == true)
    #expect(progressEvents.first?.tensorWorldBatch == true)
    #expect(progressEvents.first?.vectorizedPopulationSize == 100)
}

private struct StaticTrainingRunExecutor: AnyTrainingRunExecuting {
    let runID: TrainingRunID
    let event: TrainingRunProgressEvent

    func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        StaticTrainingRunHandle(runID: runID, event: event)
    }

    func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        StaticTrainingRunHandle(runID: runID, event: event)
    }

    func continuationSelection(from artifactRoot: URL) throws -> TrainingContinuationSelection {
        TrainingContinuationSelection(
            previousArtifactRoot: artifactRoot,
            checkpointURL: artifactRoot.appendingPathComponent("checkpoint.manasbundle", isDirectory: true),
            source: .bestCandidate
        )
    }

    func validate(_ request: TrainingRunRequest) throws {}
}

private final class StaticTrainingRunHandle: TrainingRunHandle {
    let runID: TrainingRunID
    let progress: Progress
    let events: AsyncStream<TrainingRunEvent>
    private let artifactRoot: URL

    init(runID: TrainingRunID, event: TrainingRunProgressEvent) {
        self.runID = runID
        self.progress = Progress(totalUnitCount: 1)
        self.progress.completedUnitCount = 1
        self.artifactRoot = FileManager.default.temporaryDirectory
        self.events = AsyncStream { continuation in
            continuation.yield(.progress(event))
            continuation.finish()
        }
    }

    func cancel() {}

    func wait() async throws -> TrainingRunSummary {
        TrainingRunSummary(
            runID: runID,
            artifactRoot: artifactRoot,
            terminalState: .completed,
            generationCount: 1,
            candidateCount: 100
        )
    }

    func shutdown() async {}
}
