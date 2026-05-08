import Foundation
import KuyuCore
import KuyuMLX
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

public enum KuyuCommand: Sendable {
    case runSuite(SimulationRunRequest)
    case pause
    case stop
    case exportLogs(output: KuyAtt1RunOutput, directory: URL)
    case exportDataset(
        output: KuyAtt1RunOutput,
        directory: URL,
        observationMetadata: TrainingObservationMetadata?
    )
    case trainCore(TrainingRequest)
}

public enum KuyuCommandResult: Sendable {
    case runCompleted(KuyAtt1RunOutput)
    case runPaused
    case runStopped
    case logsExported(ScenarioLogBundle)
    case datasetExported(count: Int)
    case trainingCompleted(TrainingResult)
}

@MainActor
public final class CommandSystem {
    private struct QueuedCommand {
        let command: KuyuCommand
        let continuation: CheckedContinuation<KuyuCommandResult, Error>
    }

    private let lock = NSLock()
    private var queue: [QueuedCommand] = []
    private var isProcessing = false
    private var activeControl: SimulationControl?
    private var telemetry: ((WorldStepLog) -> Void)?

    private let modelStore: ManasMLXModelStore
    private var runnerService: SimulationRunnerService
    private let logWriter: KuyAtt1LogWriter
    private let datasetExporter: TrainingDatasetExporter
    private let trainingService: TrainingService
    private let learningCampaignRunner: LearningCampaignRunner
    private lazy var trainingLoopController = TrainingLoopController(commandExecutor: self)

    public init(
        modelStore: ManasMLXModelStore,
        runnerService: SimulationRunnerService? = nil,
        logWriter: KuyAtt1LogWriter = KuyAtt1LogWriter(),
        datasetExporter: TrainingDatasetExporter = TrainingDatasetExporter(),
        trainingService: TrainingService? = nil,
        learningCampaignRunner: LearningCampaignRunner = LearningCampaignRunner()
    ) {
        self.modelStore = modelStore
        self.runnerService = runnerService ?? SimulationRunnerService(modelStore: modelStore)
        self.logWriter = logWriter
        self.datasetExporter = datasetExporter
        self.trainingService = trainingService ?? TrainingService(modelStore: modelStore)
        self.learningCampaignRunner = learningCampaignRunner
    }

    public func setTelemetry(_ handler: ((WorldStepLog) -> Void)?) {
        telemetry = handler
        trainingLoopController.setTelemetry(handler)
    }

    public func setManualActuatorStore(_ store: ManualActuatorStore?) {
        runnerService = SimulationRunnerService(modelStore: modelStore, manualActuatorStore: store)
    }

    public func startTrainingLoop(
        config: TrainingLoopConfig,
        runRequest: SimulationRunRequest,
        trainingTemplate: TrainingRequest,
        datasetRoot: URL,
        onEvent: @Sendable @escaping (TrainingLoopEvent) -> Void
    ) {
        trainingLoopController.start(
            config: config,
            runRequest: runRequest,
            trainingTemplate: trainingTemplate,
            datasetRoot: datasetRoot,
            onEvent: onEvent
        )
    }

    public func pauseTrainingLoop() async {
        await trainingLoopController.pause()
    }

    public func resumeTrainingLoop() async {
        await trainingLoopController.resume()
    }

    public func stopTrainingLoop() async {
        await trainingLoopController.stop()
    }

    public func startLearningCampaign(config: LearningCampaignRunConfig) throws -> LearningCampaignRunHandle {
        try learningCampaignRunner.start(config: config)
    }

    public func validateLearningCampaign(config: LearningCampaignRunConfig) throws {
        _ = try learningCampaignRunner.makeOrchestratorConfig(config: config)
        try learningCampaignRunner.preflight(config: config)
    }

    public func submit(_ command: KuyuCommand) async throws -> KuyuCommandResult {
        switch command {
        case .pause:
            let control = withLock { activeControl }
            if let control {
                await control.togglePause()
            }
            return .runPaused
        case .stop:
            let control = withLock { activeControl }
            if let control {
                await control.requestStop()
            }
            return .runStopped
        default:
            break
        }
        return try await withCheckedThrowingContinuation { continuation in
            let shouldStart = withLock {
                queue.append(QueuedCommand(command: command, continuation: continuation))
                if !isProcessing {
                    isProcessing = true
                    return true
                }
                return false
            }
            if shouldStart {
                Task { await processNext() }
            }
        }
    }

    private func processNext() async {
        let next: QueuedCommand? = withLock {
            guard !queue.isEmpty else {
                isProcessing = false
                return nil
            }
            return queue.removeFirst()
        }
        guard let next else { return }
        do {
            let result = try await execute(next.command)
            next.continuation.resume(returning: result)
        } catch {
            next.continuation.resume(throwing: error)
        }
        await processNext()
    }

    private func execute(_ command: KuyuCommand) async throws -> KuyuCommandResult {
        switch command {
        case .runSuite(let request):
            let control = SimulationControl()
            withLock { activeControl = control }
            defer { withLock { activeControl = nil } }
            let output = try await runSuite(request: request, control: control, telemetry: telemetry)
            return .runCompleted(output)
        case .pause:
            let control = withLock { activeControl }
            if let control {
                await control.togglePause()
            }
            return .runPaused
        case .stop:
            let control = withLock { activeControl }
            if let control {
                await control.requestStop()
            }
            return .runStopped
        case .exportLogs(let output, let directory):
            let bundle = try logWriter.write(output: output, to: directory)
            return .logsExported(bundle)
        case .exportDataset(let output, let directory, let observationMetadata):
            let outputs = try datasetExporter.write(
                output: output,
                to: directory,
                observation: observationMetadata
            )
            return .datasetExported(count: outputs.count)
        case .trainCore(let request):
            let result = try await trainingService.trainCore(request: request)
            return .trainingCompleted(result)
        }
    }

    private func runSuite(
        request: SimulationRunRequest,
        control: SimulationControl,
        telemetry: ((WorldStepLog) -> Void)?
    ) async throws -> KuyAtt1RunOutput {
        try await runnerService.run(request: request, control: control, telemetry: telemetry)
    }

    @discardableResult
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

extension CommandSystem: TrainingLoopCommandExecuting {
    public func runTrainingRunForTrainingLoop(
        config: TrainingRunConfig,
        runRequest: SimulationRunRequest,
        trainingTemplate: TrainingBackendRequest,
        datasetRoot: URL,
        observationMetadata: TrainingObservationMetadata?,
        onEvent: @Sendable @escaping (TrainingRunEvent) -> Void
    ) async -> TrainingRunResult {
        let backendBundle = ManasMLXTrainingBackendFactory().makeWorkerLocalBackend(
            activeStore: modelStore,
            runID: config.runID,
            runRequest: runRequest,
            datasetRoot: datasetRoot
        )
        let effectiveTrainingTemplate = TrainingBackendRequest(
            datasetURL: trainingTemplate.datasetURL,
            sequenceLength: trainingTemplate.sequenceLength,
            epochs: trainingTemplate.epochs,
            learningRate: trainingTemplate.learningRate,
            useAux: trainingTemplate.useAux,
            useQualityGating: trainingTemplate.useQualityGating,
            maxBatches: trainingTemplate.maxBatches,
            sourceSnapshot: backendBundle.sourceSnapshot
        )
        let orchestrator = TrainingRunOrchestrator(
            scenarioExecutor: self,
            backend: backendBundle.backend,
            datasetExporter: datasetExporter
        )
        return await orchestrator.run(
            config: config,
            runRequest: runRequest,
            trainingTemplate: effectiveTrainingTemplate,
            artifactDirectory: datasetRoot,
            observationMetadata: observationMetadata,
            onEvent: onEvent
        )
    }

    public func pauseActiveTrainingRun() async {
        let control = withLock { activeControl }
        if let control {
            await control.requestPause()
        }
    }

    public func resumeActiveTrainingRun() async {
        let control = withLock { activeControl }
        if let control {
            await control.requestResume()
        }
    }

    public func stopActiveTrainingRun() async {
        let control = withLock { activeControl }
        if let control {
            await control.requestStop()
        }
    }
}

extension CommandSystem: TrainingScenarioExecuting {
    public func runSuiteForTrainingRun(request: SimulationRunRequest) async throws -> KuyAtt1RunOutput {
        let control = SimulationControl()
        withLock { activeControl = control }
        defer { withLock { activeControl = nil } }
        return try await runSuite(request: request, control: control, telemetry: telemetry)
    }
}
