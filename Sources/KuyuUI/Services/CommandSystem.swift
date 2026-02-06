import Foundation
import KuyuCore
import KuyuMLX
import KuyuProfiles

public enum KuyuCommand: Sendable {
    case runSuite(SimulationRunRequest)
    case pause
    case stop
    case exportLogs(output: KuyAtt1RunOutput, directory: URL)
    case exportDataset(output: KuyAtt1RunOutput, directory: URL)
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

    public init(
        modelStore: ManasMLXModelStore,
        runnerService: SimulationRunnerService? = nil,
        logWriter: KuyAtt1LogWriter = KuyAtt1LogWriter(),
        datasetExporter: TrainingDatasetExporter = TrainingDatasetExporter(),
        trainingService: TrainingService? = nil
    ) {
        self.modelStore = modelStore
        self.runnerService = runnerService ?? SimulationRunnerService(modelStore: modelStore)
        self.logWriter = logWriter
        self.datasetExporter = datasetExporter
        self.trainingService = trainingService ?? TrainingService(modelStore: modelStore)
    }

    public func setTelemetry(_ handler: ((WorldStepLog) -> Void)?) {
        telemetry = handler
    }

    public func setManualActuatorStore(_ store: ManualActuatorStore?) {
        runnerService = SimulationRunnerService(modelStore: modelStore, manualActuatorStore: store)
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
        case .exportDataset(let output, let directory):
            let outputs = try datasetExporter.write(output: output, to: directory)
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
