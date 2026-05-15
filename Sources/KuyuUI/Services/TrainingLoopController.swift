import Foundation
import KuyuCore
import KuyuMLX
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

@MainActor
public protocol TrainingLoopCommandExecuting: AnyObject {
    func runTrainingRunForTrainingLoop(
        config: TrainingRunConfig,
        runRequest: SimulationRunRequest,
        trainingTemplate: TrainingBackendRequest,
        datasetRoot: URL,
        observationMetadata: TrainingObservationMetadata?,
        onEvent: @Sendable @escaping (TrainingRunEvent) -> Void
    ) async -> TrainingRunResult

    func pauseActiveTrainingRun() async
    func resumeActiveTrainingRun() async
    func stopActiveTrainingRun() async
}

public struct TrainingLoopConfig: Sendable, Equatable {
    var maxIterations: Int
    var evaluationInterval: Int
    var stopOnPass: Bool
    var patience: Int
    var minDelta: Double
    var maxConsecutiveFailures: Int
    var allowAutoBackoff: Bool
    var enableDatasetExport: Bool
    var enableTraining: Bool
}

public enum TrainingLoopEvent: Sendable, Equatable {
    case started
    case iterationStarted(Int)
    case runStarted(iteration: Int)
    case runCompleted(iteration: Int, output: KuyAtt1RunOutput, score: Double)
    case teacherRunStarted(iteration: Int, hoverThrustScale: Double)
    case teacherRunCompleted(iteration: Int, output: KuyAtt1RunOutput)
    case datasetExportStarted(iteration: Int, path: String)
    case datasetExportCompleted(iteration: Int, count: Int)
    case trainingStarted(iteration: Int, path: String, epochs: Int, learningRate: Double)
    case trainingCompleted(iteration: Int, result: TrainingResult)
    case reinforcementTrainingCompleted(iteration: Int, result: ReinforcementTrainingBackendResult)
    case backoffApplied(newLearningRate: Double)
    case paused
    case resumed
    case stopped
    case completed(summary: TrainingLoopSummary)
    case failed(message: String)
}

public struct TrainingLoopSummary: Sendable, Equatable {
    let iterations: Int
    let bestScore: Double
    let lastScore: Double
    let passed: Bool
    let failures: [String]
    let artifactDirectory: URL
    let convergence: ConvergenceSummary
    let checkpointDecision: CheckpointDecision
}

@MainActor
public final class TrainingLoopController {
    private let lock = NSLock()
    private let commandExecutor: any TrainingLoopCommandExecuting
    private var task: Task<Void, Never>?

    public init(commandExecutor: any TrainingLoopCommandExecuting) {
        self.commandExecutor = commandExecutor
    }

    public func setTelemetry(_ handler: WorldStepTelemetry?) {
        _ = handler
    }

    public func start(
        config: TrainingLoopConfig,
        runRequest: SimulationRunRequest,
        trainingTemplate: TrainingRequest,
        datasetRoot: URL,
        onEvent: @Sendable @escaping (TrainingLoopEvent) -> Void
    ) {
        withLock {
            guard task == nil else { return }
            let backendTemplate = TrainingBackendRequest(
                datasetURL: datasetRoot,
                sequenceLength: trainingTemplate.sequenceLength,
                epochs: trainingTemplate.epochs,
                learningRate: trainingTemplate.learningRate,
                useAux: trainingTemplate.useAux,
                useQualityGating: trainingTemplate.useQualityGating,
                maxBatches: trainingTemplate.maxBatches,
                sourceSnapshot: nil
            )
            let runConfig = TrainingRunConfig(
                mode: .supervised,
                maxIterations: max(1, config.maxIterations),
                minDelta: config.minDelta,
                workerCount: 1,
                enableDatasetExport: config.enableDatasetExport,
                enableTraining: config.enableTraining,
                stopOnPass: config.stopOnPass,
                parentCheckpointID: nil,
                policyID: runRequest.controller.rawValue
            )
            task = Task { [weak self] in
                guard let self else { return }
                onEvent(.started)
                let result = await self.commandExecutor.runTrainingRunForTrainingLoop(
                    config: runConfig,
                    runRequest: runRequest,
                    trainingTemplate: backendTemplate,
                    datasetRoot: datasetRoot,
                    observationMetadata: nil,
                    onEvent: { event in
                        TrainingLoopEventAdapter.present(
                            event: event,
                            trainingTemplate: backendTemplate,
                            onEvent: onEvent
                        )
                    }
                )
                TrainingLoopEventAdapter.presentCompletion(
                    result: result,
                    artifactDirectory: datasetRoot,
                    onEvent: onEvent
                )
                self.withLock { self.task = nil }
            }
        }
    }

    public func pause() async {
        await commandExecutor.pauseActiveTrainingRun()
    }

    public func resume() async {
        await commandExecutor.resumeActiveTrainingRun()
    }

    public func stop() async {
        await commandExecutor.stopActiveTrainingRun()
        onCurrentTask { $0.cancel() }
    }

    private func onCurrentTask(_ body: (Task<Void, Never>) -> Void) {
        withLock {
            guard let task else { return }
            body(task)
        }
    }

    @discardableResult
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
