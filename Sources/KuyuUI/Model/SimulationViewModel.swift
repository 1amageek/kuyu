import Configuration
import Foundation
import Logging
import Observation
import KuyuCore
import KuyuMLX

@Observable
@MainActor
final class SimulationViewModel {
    private(set) var runs: [RunRecord] = []
    var selectedRunID: UUID?
    var selectedScenarioKey: ScenarioKey?
    var isRunning = false
    var isPaused = false
    var runError: String?

    var kp: Double = 2.0
    var kd: Double = 0.25
    var yawDamping: Double = 0.2
    var hoverThrustScale: Double = 1.0
    var cutPeriodSteps: UInt64 = 2
    var determinismSelection: DeterminismSelection = .tier1
    var controllerSelection: ControllerSelection = .manasMLX

    var useEnvironmentConfig = false
    var logLevel: LogLevelOption = .info
    var logLabel: String = "kuyu.ui"
    var logDirectory: String = ""
    var trainingDatasetDirectory: String = ""
    var trainingInputDirectory: String = ""
    var modelDescriptorPath: String = KuyuUIModelPaths.defaultDescriptorPath()
    var robotProfileSelection: RobotProfileSelection = .auto

    var trainingEpochs: Int = 4
    var trainingSequenceLength: Int = 16
    var trainingLearningRate: Double = 0.001
    var trainingUseAux: Bool = true
    var trainingUseQualityGating: Bool = true
    var isTraining = false
    var lastTrainingLoss: Double?
    var isLoopRunning = false
    var isLoopPaused = false
    var loopIteration: Int = 0
    var loopBestScore: Double?
    var loopLastScore: Double?
    var loopStatusMessage: String = ""

    var loopMaxIterations: Int = 10
    var loopEvaluationInterval: Int = 1
    var loopStopOnPass: Bool = false
    var loopPatience: Int = 0
    var loopMinDelta: Double = 0.01
    var loopMaxFailures: Int = 2
    var loopAllowAutoBackoff: Bool = true

    let logStore: UILogStore
    private let commandSystem: CommandSystem
    private var logger: Logger
    private let renderSystem = RenderSystem()
    private let trainingLoopController: TrainingLoopController
    private let modelStore: ManasMLXModelStore

    init(logStore: UILogStore, commandSystem: CommandSystem? = nil) {
        self.logStore = logStore
        let store = ManasMLXModelStore()
        self.modelStore = store
        self.commandSystem = commandSystem ?? CommandSystem(modelStore: store)
        self.trainingLoopController = TrainingLoopController(modelStore: store)
        self.logger = Logger(label: "kuyu.ui")
        self.logger.logLevel = .info
    }

    var selectedRun: RunRecord? {
        guard let selectedRunID else { return runs.first }
        return runs.first { $0.id == selectedRunID }
    }

    var selectedScenario: ScenarioRunRecord? {
        guard let run = selectedRun else { return nil }
        if let selectedScenarioKey {
            return run.scenarios.first { $0.id == selectedScenarioKey }
        }
        return run.scenarios.first
    }

    func applyEnvironmentConfig() {
        let config = KuyuConfigLoader().loadFromEnvironment()
        logLevel = LogLevelOption.from(level: config.logLevel)
        logLabel = config.logLabel
        logDirectory = config.logDirectory ?? ""
        refreshLogger()
    }

    func refreshLogger() {
        var updated = Logger(label: logLabel)
        updated.logLevel = effectiveLogLevel(logLevel.level)
        logger = updated
    }

    func runBaseline() {
        guard !isRunning, !isLoopRunning else {
            emitTerminal(level: .warning, message: "Run already in progress")
            return
        }
        runError = nil
        isRunning = true
        isPaused = false

        let gains: ImuRateDampingCutGains
        do {
            gains = try ImuRateDampingCutGains(
                kp: kp,
                kd: kd,
                yawDamping: yawDamping,
                hoverThrustScale: hoverThrustScale
            )
        } catch {
            isRunning = false
            emitError("Invalid gains", error: error)
            return
        }

        let determinism: DeterminismConfig
        do {
            determinism = try determinismSelection.makeConfig()
        } catch {
            isRunning = false
            emitError("Invalid determinism config", error: error)
            return
        }

        let request = SimulationRunRequest(
            controller: controllerSelection,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            modelDescriptorPath: resolvedDescriptorPath(),
            overrideParameters: preflightParameters(),
            useAux: trainingUseAux,
            useQualityGating: trainingUseQualityGating
        )

        emitTerminal(
            level: .notice,
            message: "Run started (single)",
            metadata: [
                "controller": controllerSelection.rawValue,
                "tier": "\(determinism.tier)",
                "cutPeriod": "\(cutPeriodSteps)"
            ]
        )

        Task(priority: .userInitiated) { [request] in
            do {
                let result = try await commandSystem.submit(.runSuite(request))
                if case .runCompleted(let output) = result {
                    let record = Self.buildRunRecord(output: output)
                    self.isRunning = false
                    self.isPaused = false
                    self.runs.insert(record, at: 0)
                    self.selectedRunID = record.id
                    self.selectedScenarioKey = record.scenarios.first?.id
                    self.emitTerminal(
                        level: .info,
                        message: "Run completed",
                        metadata: [
                            "passed": "\(record.output.summary.suitePassed)"
                        ]
                    )
                    if !record.output.summary.suitePassed {
                        self.emitFailureDetails(output: record.output)
                    }
                }
            } catch is CancellationError {
                self.isRunning = false
                self.isPaused = false
                self.emitTerminal(level: .notice, message: "Run stopped")
            } catch {
                self.isRunning = false
                self.isPaused = false
                self.emitError("Run failed", error: error)
            }
        }
    }

    func pauseRun() {
        Task {
            _ = try? await commandSystem.submit(.pause)
            isPaused.toggle()
            let message = isPaused ? "Paused" : "Resumed"
            emitTerminal(level: .notice, message: message)
        }
    }

    func stopRun() {
        Task {
            _ = try? await commandSystem.submit(.stop)
            isPaused = false
            emitTerminal(level: .notice, message: "Stop requested")
        }
    }

    func exportLogs() {
        guard let run = selectedRun else { return }
        let trimmed = logDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            emitError("Log directory is empty")
            return
        }
        let url = URL(fileURLWithPath: trimmed, isDirectory: true)
        Task {
            do {
                let result = try await commandSystem.submit(.exportLogs(output: run.output, directory: url))
                if case .logsExported(let bundle) = result {
                    emitTerminal(
                        level: .info,
                        message: "Logs exported",
                        metadata: [
                            "path": "\(url.path)",
                            "count": "\(bundle.logs.count)"
                        ]
                    )
                }
            } catch {
                emitError("Export failed", error: error)
            }
        }
    }

    func exportTrainingDataset() {
        guard let run = selectedRun else {
            emitError("No run selected")
            return
        }
        let trimmed = trainingDatasetDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            emitError("Training dataset directory is empty")
            return
        }

        let url = URL(fileURLWithPath: trimmed, isDirectory: true)
        Task {
            do {
                let result = try await commandSystem.submit(.exportDataset(output: run.output, directory: url))
                if case .datasetExported(let count) = result {
                    emitTerminal(
                        level: .info,
                        message: "Training dataset exported",
                        metadata: [
                            "path": "\(url.path)",
                            "count": "\(count)"
                        ]
                    )
                }
            } catch {
                emitError("Training dataset export failed", error: error)
            }
        }
    }

    func trainCoreModel() {
        guard !isTraining else {
            emitTerminal(level: .warning, message: "Training already in progress")
            return
        }
        let trimmed = trainingInputDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            emitError("Training dataset directory is empty")
            return
        }

        let url = URL(fileURLWithPath: trimmed, isDirectory: true)
        isTraining = true
        lastTrainingLoss = nil

        emitTerminal(level: .notice, message: "Training started", metadata: [
            "epochs": "\(trainingEpochs)",
            "sequence": "\(trainingSequenceLength)",
            "aux": trainingUseAux ? "true" : "false"
        ])

        let request = TrainingRequest(
            datasetURL: url,
            sequenceLength: trainingSequenceLength,
            epochs: trainingEpochs,
            learningRate: trainingLearningRate,
            useAux: trainingUseAux,
            useQualityGating: trainingUseQualityGating
        )

        Task(priority: .userInitiated) { [request] in
            do {
                let result = try await commandSystem.submit(.trainCore(request))
                guard case .trainingCompleted(let output) = result else { return }
                isTraining = false
                lastTrainingLoss = output.finalLoss
                emitTerminal(level: .info, message: "Training completed", metadata: [
                    "finalLoss": String(format: "%.6f", output.finalLoss),
                    "epochs": "\(output.epochs)"
                ])
            } catch {
                isTraining = false
                emitError("Training failed", error: error)
            }
        }
    }

    func startTrainingLoop() {
        guard !isLoopRunning, !isRunning else {
            emitTerminal(level: .warning, message: "Loop already running")
            return
        }

        let gains: ImuRateDampingCutGains
        do {
            gains = try ImuRateDampingCutGains(
                kp: kp,
                kd: kd,
                yawDamping: yawDamping,
                hoverThrustScale: hoverThrustScale
            )
        } catch {
            emitError("Invalid gains", error: error)
            return
        }

        let determinism: DeterminismConfig
        do {
            determinism = try determinismSelection.makeConfig()
        } catch {
            emitError("Invalid determinism config", error: error)
            return
        }

        let loopController: ControllerSelection
        if controllerSelection == .manasMLX {
            loopController = controllerSelection
        } else {
            loopController = .manasMLX
            emitTerminal(level: .warning, message: "Training loop forces ManasMLX controller")
        }

        let runRequest = SimulationRunRequest(
            controller: loopController,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            modelDescriptorPath: resolvedDescriptorPath(),
            overrideParameters: preflightParameters(),
            useAux: trainingUseAux,
            useQualityGating: trainingUseQualityGating
        )

        let trimmed = trainingDatasetDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let datasetRoot: URL
        if trimmed.isEmpty {
            datasetRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-loop-\(UUID().uuidString)", isDirectory: true)
        } else {
            datasetRoot = URL(fileURLWithPath: trimmed, isDirectory: true)
                .appendingPathComponent("loop-\(UUID().uuidString)", isDirectory: true)
        }

        let trainingTemplate = TrainingRequest(
            datasetURL: datasetRoot,
            sequenceLength: trainingSequenceLength,
            epochs: trainingEpochs,
            learningRate: trainingLearningRate,
            useAux: trainingUseAux,
            useQualityGating: trainingUseQualityGating
        )

        let config = TrainingLoopConfig(
            maxIterations: loopMaxIterations,
            evaluationInterval: loopEvaluationInterval,
            stopOnPass: loopStopOnPass,
            patience: loopPatience,
            minDelta: loopMinDelta,
            maxConsecutiveFailures: loopMaxFailures,
            allowAutoBackoff: loopAllowAutoBackoff
        )

        isLoopRunning = true
        isLoopPaused = false
        loopIteration = 0
        loopBestScore = nil
        loopLastScore = nil
        loopStatusMessage = "Loop started"
        emitTerminal(level: .notice, message: "Training loop started", metadata: [
            "controller": loopController.rawValue,
            "iterations": "\(loopMaxIterations)",
            "evalInterval": "\(loopEvaluationInterval)",
            "stopOnPass": loopStopOnPass ? "true" : "false"
        ])
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if isPreview {
            emitTerminal(level: .notice, message: "Preview batch cap enabled", metadata: [
                "maxBatches": "8"
            ])
        }
        emitTerminal(level: .notice, message: "Training config", metadata: [
            "sequence": "\(trainingSequenceLength)",
            "epochs": "\(trainingEpochs)",
            "lr": String(format: "%.6f", trainingLearningRate),
            "aux": trainingUseAux ? "true" : "false",
            "qualityGate": trainingUseQualityGating ? "true" : "false"
        ])

        Task {
            trainingLoopController.start(
                config: config,
                runRequest: runRequest,
                trainingTemplate: trainingTemplate,
                datasetRoot: datasetRoot
            ) { [weak self] event in
                guard let self else { return }
                Task { @MainActor in
                    self.handleLoopEvent(event)
                }
            }
        }
    }

    func pauseTrainingLoop() {
        guard isLoopRunning else { return }
        Task {
            await trainingLoopController.pause()
            await MainActor.run {
                isLoopPaused = true
                loopStatusMessage = "Paused"
                emitTerminal(level: .notice, message: "Training loop paused")
            }
        }
    }

    func resumeTrainingLoop() {
        guard isLoopRunning else { return }
        Task {
            await trainingLoopController.resume()
            await MainActor.run {
                isLoopPaused = false
                loopStatusMessage = "Resumed"
                emitTerminal(level: .notice, message: "Training loop resumed")
            }
        }
    }

    func stopTrainingLoop() {
        guard isLoopRunning else { return }
        Task {
            await trainingLoopController.stop()
            await MainActor.run {
                isLoopPaused = false
                loopStatusMessage = "Stopping"
                emitTerminal(level: .notice, message: "Training loop stop requested")
            }
        }
    }

    private func handleLoopEvent(_ event: TrainingLoopEvent) {
        switch event {
        case .started:
            loopStatusMessage = "Running"
        case .iterationStarted(let iteration):
            loopIteration = iteration
            loopStatusMessage = "Iteration \(iteration)"
            emitTerminal(level: .notice, message: "Loop iteration started", metadata: [
                "iter": "\(iteration)"
            ])
        case .runStarted(let iteration):
            emitTerminal(level: .notice, message: "Loop run started", metadata: [
                "iter": "\(iteration)"
            ])
        case .runCompleted(let iteration, let output, let score):
            loopIteration = iteration
            loopLastScore = score
            if loopBestScore == nil || score > (loopBestScore ?? -Double.greatestFiniteMagnitude) {
                loopBestScore = score
            }
            let record = Self.buildRunRecord(output: output)
            runs.insert(record, at: 0)
            selectedRunID = record.id
            selectedScenarioKey = record.scenarios.first?.id
            let aggregate = output.summary.aggregate
            let overshoot = aggregate.worstOvershootDegrees.map { String(format: "%.2f", $0) } ?? "n/a"
            let recovery = aggregate.averageRecoveryTime.map { String(format: "%.2f", $0) } ?? "n/a"
            let hf = aggregate.averageHfStabilityScore.map { String(format: "%.2f", $0) } ?? "n/a"
            emitTerminal(level: .info, message: "Loop run completed", metadata: [
                "iter": "\(iteration)",
                "score": String(format: "%.3f", score),
                "overshoot": overshoot,
                "recovery": recovery,
                "hf": hf
            ])
        case .datasetExportStarted(let iteration, let path):
            emitTerminal(level: .notice, message: "Dataset export started", metadata: [
                "iter": "\(iteration)",
                "path": path
            ])
        case .datasetExportCompleted(let iteration, let count):
            emitTerminal(level: .info, message: "Dataset export completed", metadata: [
                "iter": "\(iteration)",
                "count": "\(count)"
            ])
        case .trainingStarted(let iteration, let path, let epochs, let learningRate):
            emitTerminal(level: .notice, message: "Training started", metadata: [
                "iter": "\(iteration)",
                "path": path,
                "epochs": "\(epochs)",
                "lr": String(format: "%.6f", learningRate)
            ])
        case .trainingCompleted(let iteration, let result):
            lastTrainingLoss = result.finalLoss
            emitTerminal(level: .info, message: "Training completed", metadata: [
                "iter": "\(iteration)",
                "loss": String(format: "%.6f", result.finalLoss)
            ])
        case .backoffApplied(let newLearningRate):
            trainingLearningRate = newLearningRate
            emitTerminal(level: .notice, message: "Learning rate backoff", metadata: [
                "lr": String(format: "%.6f", newLearningRate)
            ])
        case .paused:
            isLoopPaused = true
            loopStatusMessage = "Paused"
        case .resumed:
            isLoopPaused = false
            loopStatusMessage = "Running"
        case .stopped:
            isLoopRunning = false
            isLoopPaused = false
            loopStatusMessage = "Stopped"
        case .completed(let summary):
            isLoopRunning = false
            isLoopPaused = false
            loopBestScore = summary.bestScore
            loopLastScore = summary.lastScore
            loopStatusMessage = summary.passed ? "Completed (passed)" : "Completed"
            emitTerminal(level: .info, message: "Training loop completed", metadata: [
                "iterations": "\(summary.iterations)",
                "bestScore": String(format: "%.3f", summary.bestScore)
            ])
        case .failed(let message):
            loopStatusMessage = "Failed"
            emitTerminal(level: .error, message: message)
        }
    }

    func clearRuns() {
        runs.removeAll()
        selectedRunID = nil
        selectedScenarioKey = nil
        runError = nil
    }

    func insertRun(_ run: RunRecord) {
        runs.insert(run, at: 0)
        selectedRunID = run.id
        selectedScenarioKey = run.scenarios.first?.id
    }

    func setModelDescriptorPath(_ path: String, source: String) {
        modelDescriptorPath = path
        emitTerminal(level: .info, message: "Model descriptor set", metadata: [
            "source": source,
            "path": path
        ])
    }

    private static func buildRunRecord(output: KuyAtt1RunOutput) -> RunRecord {
        let evaluationsByKey = Dictionary(
            uniqueKeysWithValues: output.result.evaluations.map {
                (ScenarioKey(scenarioId: $0.scenarioId, seed: $0.seed), $0)
            }
        )

        let scenarios: [ScenarioRunRecord] = output.logs.compactMap { entry in
            guard let evaluation = evaluationsByKey[entry.key] else { return nil }
            let metrics = ScenarioMetricsBuilder.build(log: entry.log)
            return ScenarioRunRecord(
                id: entry.key,
                evaluation: evaluation,
                log: entry.log,
                metrics: metrics
            )
        }.sorted { lhs, rhs in
            if lhs.id.scenarioId.rawValue == rhs.id.scenarioId.rawValue {
                return lhs.id.seed.rawValue < rhs.id.seed.rawValue
            }
            return lhs.id.scenarioId.rawValue < rhs.id.scenarioId.rawValue
        }

        return RunRecord(output: output, scenarios: scenarios)
    }

    private func emitError(_ message: String, error: Error? = nil) {
        let detail: String
        if let error {
            detail = "\(message): \(error)"
        } else {
            detail = message
        }
        runError = detail
        emitTerminal(level: .error, message: detail)
    }

    private func effectiveLogLevel(_ level: Logger.Level) -> Logger.Level {
        let order: [Logger.Level] = [.trace, .debug, .info, .notice, .warning, .error, .critical]
        guard let levelIndex = order.firstIndex(of: level),
              let errorIndex = order.firstIndex(of: .error) else {
            return level
        }
        return levelIndex > errorIndex ? .error : level
    }

    private func resolvedDescriptorPath() -> String {
        let resolved = KuyuUIModelPaths.resolveDescriptorPath(modelDescriptorPath)
        if resolved != modelDescriptorPath {
            modelDescriptorPath = resolved
            emitTerminal(level: .warning, message: "Model descriptor not found, using fallback", metadata: [
                "path": resolved
            ])
        }
        return resolved
    }

    private func preflightParameters() -> QuadrotorParameters? {
        let path = resolvedDescriptorPath()
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        do {
            let loader = RobotModelLoader()
            let loaded = try loader.loadDescriptor(path: trimmed)
            let parameters = try loader.loadQuadrotorParameters(descriptor: loaded)
            emitTerminal(level: .info, message: "Model loaded", metadata: [
                "path": trimmed
            ])
            return parameters
        } catch {
            emitTerminal(level: .warning, message: "Model load failed, using baseline", metadata: [
                "error": "\(error)"
            ])
            return QuadrotorParameters.baseline
        }
    }

    func emitTerminal(
        level: Logger.Level,
        message: String,
        metadata: [String: String] = [:]
    ) {
        let entry = UILogEntry(
            timestamp: Date(),
            level: level,
            label: logLabel,
            message: message,
            metadata: metadata
        )
        logStore.emit(entry)
    }

    private func emitFailureDetails(output: KuyAtt1RunOutput) {
        let failures = output.result.evaluations.filter { !$0.passed }
        if failures.isEmpty { return }

        emitTerminal(level: .warning, message: "Scenario failures", metadata: [
            "count": "\(failures.count)"
        ])

        for evaluation in failures {
            let reason = evaluation.failures.isEmpty ? "safety envelope violation" : evaluation.failures.joined(separator: ", ")
            emitTerminal(level: .warning, message: evaluation.scenarioId.rawValue, metadata: [
                "seed": "\(evaluation.seed.rawValue)",
                "reason": reason,
                "maxTilt": String(format: "%.2f", evaluation.maxTiltDegrees),
                "maxOmega": String(format: "%.2f", evaluation.maxOmega),
                "sustained": String(format: "%.3f", evaluation.sustainedViolationSeconds)
            ])
        }
    }

    func sceneState(at time: Double) -> SceneState? {
        guard let scenario = selectedScenario else { return nil }
        return renderSystem.sceneState(for: scenario.log, time: time)
    }

    func renderAssetInfo() -> RenderAssetInfo? {
        let path = resolvedDescriptorPath()
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let loader = RobotModelLoader()
            let loaded = try loader.loadDescriptor(path: trimmed)
            let url = loader.loadRenderURL(descriptor: loaded)
            return RenderAssetInfo(
                name: loaded.descriptor.name,
                url: url,
                format: loaded.descriptor.renderFormat
            )
        } catch {
            emitTerminal(level: .warning, message: "Render asset load failed", metadata: [
                "error": "\(error)"
            ])
            return nil
        }
    }

    func resolvedProfile(for scenario: ScenarioRunRecord?) -> RobotProfile {
        switch robotProfileSelection {
        case .quadrotor:
            return .quadrotor
        case .generic:
            return .generic
        case .auto:
            let scenarioId = scenario?.id.scenarioId.rawValue ?? ""
            if scenarioId.contains("KUY-ATT") {
                return .quadrotor
            }
            return .generic
        }
    }
}
