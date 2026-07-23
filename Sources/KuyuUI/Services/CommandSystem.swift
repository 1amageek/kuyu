import Foundation
import KuyuCore
import KuyuMLX
import KuyuMLXTrainingRuntime
import KuyuPhysics
import KuyuScenarios
import KuyuTraining
import KuyuWorkerRuntime

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
}

public enum KuyuCommandResult: Sendable {
    case runCompleted(KuyAtt1RunOutput)
    case runPaused
    case runStopped
    case logsExported(ScenarioLogBundle)
    case datasetExported(count: Int)
}

@MainActor
public final class CommandSystem {
    private struct QueuedCommand {
        let command: KuyuCommand
        let continuation: CheckedContinuation<KuyuCommandResult, Error>
    }

    private var queue: [QueuedCommand] = []
    private var isProcessing = false
    private var activeControl: SimulationControl?
    private var telemetry: WorldStepTelemetry?

    private let modelStore: ManasMLXModelStore
    private var runnerService: SimulationRunnerService
    private let logWriter: KuyAtt1LogWriter
    private let datasetExporter: TrainingDatasetExporter
    private let trainingRunExecutor: any AnyTrainingRunExecuting
    private let continuationSelector: any TrainingContinuationSelecting

    public init(
        modelStore: ManasMLXModelStore,
        runnerService: SimulationRunnerService? = nil,
        logWriter: KuyAtt1LogWriter = KuyAtt1LogWriter(),
        datasetExporter: TrainingDatasetExporter = TrainingDatasetExporter(),
        trainingRunExecutor: (any AnyTrainingRunExecuting)? = nil,
        continuationSelector: (any TrainingContinuationSelecting)? = nil
    ) {
        self.modelStore = modelStore
        self.runnerService = runnerService ?? SimulationRunnerService(modelStore: modelStore)
        self.logWriter = logWriter
        self.datasetExporter = datasetExporter
        self.trainingRunExecutor = trainingRunExecutor ?? Self.defaultTrainingRunExecutor()
        self.continuationSelector = continuationSelector
            ?? TrainingRunExecutorContinuationSelector(
                executor: trainingRunExecutor ?? ManasMLXTrainingRunExecutor()
            )
    }

    public func setTelemetry(_ handler: WorldStepTelemetry?) {
        telemetry = handler
    }

    public func setManualActuatorStore(_ store: ManualActuatorStore?) {
        runnerService = SimulationRunnerService(modelStore: modelStore, manualActuatorStore: store)
    }

    public func startTrainingRun(request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        try await trainingRunExecutor.start(request)
    }

    public func resumeTrainingRun(request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        try await trainingRunExecutor.resume(request)
    }

    public func reconnectTrainingRun(
        artifactRoot: URL
    ) async throws -> (any TrainingRunHandle)? {
        try await trainingRunExecutor.reconnect(artifactRoot: artifactRoot)
    }

    public func learningCampaignContinuationSelection(
        from artifactRoot: URL
    ) throws -> TrainingContinuationSelection {
        try continuationSelector.continuationSelection(from: artifactRoot)
    }

    public func validateLearningCampaign(request: TrainingRunRequest) throws {
        try trainingRunExecutor.validate(request)
    }

    private static func defaultTrainingRunExecutor() -> any AnyTrainingRunExecuting {
        let executablePath = KuyuUIModelPaths.defaultKuyuExecutablePath()
        guard !executablePath.isEmpty else {
            return UnavailableTrainingRunExecutor(
                reason: "the kuyu worker executable could not be resolved"
            )
        }
        do {
            let configuration = try ManasMLXTrainingWorkerProcessConfigurationFactory().userCache(
                executableURL: URL(fileURLWithPath: executablePath, isDirectory: false)
            )
            return ManasMLXTrainingRunProcessExecutor(configuration: configuration)
        } catch {
            return UnavailableTrainingRunExecutor(reason: String(describing: error))
        }
    }

    public func submit(_ command: KuyuCommand) async throws -> KuyuCommandResult {
        switch command {
        case .pause:
            await activeControl?.togglePause()
            return .runPaused
        case .stop:
            await activeControl?.requestStop()
            return .runStopped
        default:
            break
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.append(QueuedCommand(command: command, continuation: continuation))
            if !isProcessing {
                isProcessing = true
                Task { await processNext() }
            }
        }
    }

    private func processNext() async {
        guard !queue.isEmpty else {
            isProcessing = false
            return
        }
        let next = queue.removeFirst()
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
            activeControl = control
            defer { activeControl = nil }
            let output = try await runSuite(request: request, control: control, telemetry: telemetry)
            return .runCompleted(output)
        case .pause:
            await activeControl?.togglePause()
            return .runPaused
        case .stop:
            await activeControl?.requestStop()
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
        }
    }

    private func runSuite(
        request: SimulationRunRequest,
        control: SimulationControl,
        telemetry: WorldStepTelemetry?
    ) async throws -> KuyAtt1RunOutput {
        let runnerService = self.runnerService
        return try await runnerService.run(request: request, control: control, telemetry: telemetry)
    }
}

extension CommandSystem: TrainingScenarioExecuting {
    public func runSuiteForTrainingRun(request: SimulationRunRequest) async throws -> TrainingScenarioRunOutput {
        let control = SimulationControl()
        activeControl = control
        defer { activeControl = nil }
        let output = try await runSuite(request: request, control: control, telemetry: telemetry)
        return TrainingScenarioRunOutput(kuyAtt1: output)
    }
}
