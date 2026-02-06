import Configuration
import Foundation
import Logging
import Observation
import KuyuCore
import KuyuMLX
import KuyuProfiles

@Observable
@MainActor
public final class SimulationViewModel {
    struct TrainingModelInfo: Identifiable, Hashable, Sendable {
        let id: UUID
        var name: String
        var createdAt: Date
        var lastTrainedAt: Date?
        var hasSupervisedBootstrap: Bool
        var storageURL: URL
    }

    private struct ModelContext {
        let store: ManasMLXModelStore
        let commandSystem: CommandSystem
        let trainingLoopController: TrainingLoopController
    }

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
    var determinismSelection: DeterminismSelection = .tier1 {
        didSet {
            emitUIAction(level: .info, message: "Determinism tier changed", action: "setDeterminismTier", metadata: [
                "value": determinismSelection.rawValue
            ])
        }
    }
    var controllerSelection: ControllerSelection = .manasMLX {
        didSet {
            emitUIAction(level: .info, message: "Controller selection changed", action: "setController", metadata: [
                "value": controllerSelection.rawValue
            ])
        }
    }
    var taskMode: SimulationTaskMode = .attitude {
        didSet {
            refreshManualActuatorLayout()
            emitUIAction(level: .info, message: "Task mode changed", action: "setTaskMode", metadata: [
                "value": taskMode.rawValue
            ])
        }
    }

    var useEnvironmentConfig = false
    var logLevel: LogLevelOption = .info
    var logLabel: String = "kuyu.ui"
    var logDirectory: String = ""
    var trainingDatasetDirectory: String = ""
    var trainingInputDirectory: String = ""
    var modelDescriptorPath: String = KuyuUIModelPaths.defaultDescriptorPath() {
        didSet {
            descriptorCachePath = nil
            descriptorCache = nil
            descriptorCacheError = nil
        }
    }
    var useRenderAssets: Bool = false {
        didSet {
            emitUIAction(level: .info, message: "Render assets toggled", action: "toggleRenderAssets", metadata: [
                "enabled": "\(useRenderAssets)"
            ])
        }
    }

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
    var liveScene: SceneState?
    var liveSampleStride: Int = 33
    private let targetRenderFPS: Double = 30.0
    private var autoStridePending = true
    private var lastLiveStepTime: Double?
    private var activeLoopController: ControllerSelection?
    private var descriptorCachePath: String?
    private var descriptorCache: LoadedRobotDescriptor?
    private var descriptorCacheError: String?
    private var lastTelemetryLogTime: Double?
    var lastActuatorValues: [ActuatorValue] = []
    var lastDriveIntents: [DriveIntent] = []
    var lastReflexCorrections: [ReflexCorrection] = []
    var lastActuatorTelemetry: ActuatorTelemetrySnapshot? = nil
    var lastMotorNerveTrace: MotorNerveTrace? = nil
    var lastSensorSamples: [ChannelSample] = []
    var manualActuatorEnabled: Bool = false {
        didSet {
            manualActuatorStore.isEnabled = manualActuatorEnabled
            emitUIAction(level: .info, message: "Manual actuator override", action: "toggleManualActuator", metadata: [
                "enabled": "\(manualActuatorEnabled)"
            ])
        }
    }
    var manualActuatorLinked: Bool = true {
        didSet {
            emitUIAction(level: .info, message: "Manual actuator linking", action: "toggleManualActuatorLink", metadata: [
                "linked": "\(manualActuatorLinked)"
            ])
        }
    }
    var manualActuatorMaster: Double = 0.0 {
        didSet { setManualActuatorAll(value: manualActuatorMaster) }
    }
    var manualActuatorValues: [Double] = [0.0, 0.0, 0.0, 0.0] {
        didSet { manualActuatorStore.update(values: manualActuatorValues) }
    }
    var trainingLossSamples: [MetricSample] = []
    var loopScoreSamples: [MetricSample] = []
    var overshootSamples: [MetricSample] = []
    var recoverySamples: [MetricSample] = []
    var hfSamples: [MetricSample] = []

    var loopMaxIterations: Int = 10
    var loopEvaluationInterval: Int = 1
    var loopStopOnPass: Bool = false
    var loopPatience: Int = 0
    var loopMinDelta: Double = 0.01
    var loopMaxFailures: Int = 2
    var loopAllowAutoBackoff: Bool = true

    let logStore: UILogStore
    private var commandSystem: CommandSystem
    private var logger: Logger
    private let renderSystem = RenderSystem()
    private var trainingLoopController: TrainingLoopController
    private var modelStore: ManasMLXModelStore
    private let manualActuatorStore = ManualActuatorStore()
    private var lastManualActuatorLogTime: TimeInterval = 0
    private var lastManualActuatorLoggedValues: [Double] = [0.0, 0.0, 0.0, 0.0]
    private var modelContexts: [UUID: ModelContext] = [:]
    private var logObserverInstalled = false
    var availableModels: [TrainingModelInfo] = []
    private var activeModelID: UUID?
    var selectedModelID: UUID?
    private var activeParameters: ReferenceQuadrotorParameters?
    private var isPreviewEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    public init(logStore: UILogStore, commandSystem: CommandSystem? = nil) {
        self.logStore = logStore
        let store = ManasMLXModelStore()
        self.modelStore = store
        self.commandSystem = commandSystem ?? CommandSystem(modelStore: store)
        self.trainingLoopController = TrainingLoopController(modelStore: store)
        self.logger = Logger(label: "kuyu.ui")
        self.logger.logLevel = .info

        let telemetry: (WorldStepLog) -> Void = { [weak self] step in
            self?.recordLiveStep(step)
        }
        self.commandSystem.setTelemetry(telemetry)
        self.trainingLoopController.setTelemetry(telemetry)
        self.commandSystem.setManualActuatorStore(manualActuatorStore)
        manualActuatorStore.isEnabled = manualActuatorEnabled
        manualActuatorStore.update(values: manualActuatorValues)
        refreshManualActuatorLayout()
        manualActuatorMaster = manualActuatorValues.first ?? 0.0
        installLogObserverIfNeeded()

        loadPersistedModelsOrFallback(defaultStore: store)
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

    var selectedModel: TrainingModelInfo? {
        guard let selectedModelID else { return nil }
        return availableModels.first { $0.id == selectedModelID }
    }

    private func updateSelectedModel(_ update: (inout TrainingModelInfo) -> Void) {
        guard let selectedModelID,
              let index = availableModels.firstIndex(where: { $0.id == selectedModelID }) else { return }
        update(&availableModels[index])
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

    private func installLogObserverIfNeeded() {
        guard !logObserverInstalled else { return }
        logObserverInstalled = true
        logStore.setEntryObserver { [weak self] entry in
            self?.handleLogEntry(entry)
        }
    }

    private func handleLogEntry(_ entry: UILogEntry) {
        guard entry.label == "kuyu.manas" else { return }
        switch entry.message {
        case "ManasMLX training progress":
            guard let lossString = entry.metadata["loss"],
                  let loss = Double(lossString) else { return }
            let time = trainingLossSampleTime(entry)
            trainingLossSamples.append(MetricSample(time: time, value: loss))
        case "ManasMLX training completed":
            guard let lossString = entry.metadata["finalLoss"],
                  let loss = Double(lossString) else { return }
            let time = trainingLossSampleTime(entry)
            trainingLossSamples.append(MetricSample(time: time, value: loss))
        default:
            break
        }
    }

    private func trainingLossSampleTime(_ entry: UILogEntry) -> Double {
        guard let epochString = entry.metadata["epoch"],
              let batchString = entry.metadata["batch"],
              let totalString = entry.metadata["total"],
              let epoch = Int(epochString),
              let batch = Int(batchString),
              let total = Int(totalString),
              epoch > 0,
              total > 0 else {
            return Double(trainingLossSamples.count + 1)
        }
        let index = ((epoch - 1) * total) + batch
        return Double(max(index, 1))
    }

    func setManualActuatorValue(index: Int, value: Double) {
        refreshManualActuatorLayout()
        guard index >= 0 && index < manualActuatorValues.count else { return }
        let clamped = min(max(value, 0.0), 1.0)
        if manualActuatorLinked {
            setManualActuatorAll(value: clamped)
            manualActuatorMaster = clamped
            return
        }
        manualActuatorValues[index] = clamped
        manualActuatorStore.update(values: manualActuatorValues)
        emitManualActuatorUpdate(reason: "per-motor")
    }

    func setManualActuatorValuePhysical(index: Int, value: Double) {
        let range = manualActuatorPhysicalRange(index: index)
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let span = max(range.upperBound - range.lowerBound, 1e-9)
        let normalized = (clamped - range.lowerBound) / span
        setManualActuatorValue(index: index, value: normalized)
    }

    func manualActuatorValuePhysical(index: Int) -> Double {
        guard index >= 0, index < manualActuatorValues.count else { return 0.0 }
        let range = manualActuatorPhysicalRange(index: index)
        let span = range.upperBound - range.lowerBound
        return range.lowerBound + (manualActuatorValues[index] * span)
    }

    func setManualActuatorMasterPhysicalValue(_ value: Double) {
        let range = manualActuatorPhysicalRange(index: 0)
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let span = max(range.upperBound - range.lowerBound, 1e-9)
        manualActuatorMaster = (clamped - range.lowerBound) / span
    }

    func manualActuatorMasterPhysicalValue() -> Double {
        let range = manualActuatorPhysicalRange(index: 0)
        let span = range.upperBound - range.lowerBound
        return range.lowerBound + (manualActuatorMaster * span)
    }

    func manualActuatorPhysicalRange(index: Int) -> ClosedRange<Double> {
        let ranges = manualActuatorChannelRanges()
        guard index >= 0, index < ranges.count else { return 0.0...1.0 }
        return ranges[index]
    }

    func setHoverThrustScale(_ value: Double, source: String) {
        if isLoopRunning || isTraining {
            emitUIAction(level: .warning, message: "Hover thrust scale change blocked during training loop", action: "setHoverThrustScale", metadata: [
                "source": source,
                "reason": "trainingLoopActive"
            ])
            return
        }
        let clamped = max(0.01, value)
        hoverThrustScale = clamped
        emitUIAction(level: .info, message: "Hover thrust scale updated", action: "setHoverThrustScale", metadata: [
            "source": source,
            "value": String(format: "%.3f", clamped)
        ])
        guard taskMode == .singleLift else { return }
        guard isRunning, !isLoopRunning, !isTraining else {
            emitUIAction(level: .warning, message: "Hover thrust scale update deferred", action: "hoverTestDeferred", metadata: [
                "reason": isLoopRunning ? "loopRunning" : (isTraining ? "training" : "notRunning")
            ])
            return
        }
        guard let parameters = activeParameters else {
            emitUIAction(level: .warning, message: "Hover thrust scale override missing parameters", action: "hoverTestOverride", metadata: [
                "reason": "missingParameters"
            ])
            return
        }
        let hoverThrust = parameters.mass * parameters.gravity * clamped
        let baseThrottle = min(max(hoverThrust / max(parameters.maxThrust, 1e-6), 0.0), 1.0)
        manualActuatorLinked = true
        manualActuatorEnabled = true
        manualActuatorMaster = baseThrottle
        emitUIAction(level: .notice, message: "Hover thrust override applied", action: "hoverTestOverride", metadata: [
            "hoverThrust": String(format: "%.3f", hoverThrust),
            "maxThrust": String(format: "%.3f", parameters.maxThrust),
            "baseThrottle": String(format: "%.3f", baseThrottle)
        ])
    }

    func setManualActuatorAll(value: Double) {
        refreshManualActuatorLayout()
        let clamped = min(max(value, 0.0), 1.0)
        manualActuatorValues = Array(repeating: clamped, count: manualActuatorValues.count)
        manualActuatorStore.update(values: manualActuatorValues)
        emitManualActuatorUpdate(reason: "linked")
    }

    private func taskProfileMetadata() -> [String: String] {
        let motorNerveProfile = currentMotorNerveProfile()
        switch taskMode {
        case .attitude:
            return [
                "suite": "KUY-ATT-1",
                "motorNerveProfile": motorNerveProfile
            ]
        case .lift:
            return [
                "suite": "KUY-LIFT-1",
                "motorNerveProfile": motorNerveProfile
            ]
        case .singleLift:
            return [
                "suite": "KUY-SLIFT-1",
                "motorNerveProfile": motorNerveProfile
            ]
        }
    }

    private func emitTaskMismatchWarnings(modelPath: String?) {
        guard let modelPath else { return }
        if taskMode == .singleLift && isQuadDescriptorPath(modelPath) {
            emitUIAction(level: .warning, message: "Single Lift task using quad model descriptor", action: "taskDescriptorMismatch", metadata: [
                "path": modelPath,
                "reason": "singleLiftUsesQuad"
            ])
        }
        if taskMode != .singleLift && isSinglePropDescriptorPath(modelPath) {
            emitUIAction(level: .warning, message: "Quad task using single-prop model descriptor", action: "taskDescriptorMismatch", metadata: [
                "path": modelPath,
                "reason": "quadUsesSingleProp"
            ])
        }
    }

    private func isQuadDescriptorPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("quad") || lower.contains("quadref")
    }

    private func isSinglePropDescriptorPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("singleprop") || lower.contains("single-prop") || lower.contains("slift")
    }

    private func desiredDescriptorPath(for task: SimulationTaskMode) -> String {
        switch task {
        case .singleLift:
            return KuyuUIModelPaths.defaultSinglePropDescriptorPath()
        case .attitude, .lift:
            return KuyuUIModelPaths.defaultDescriptorPath()
        }
    }

    private func ensureDescriptorForTask(reason: String) -> String {
        let trimmed = modelDescriptorPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let desired = desiredDescriptorPath(for: taskMode)
        if trimmed.isEmpty {
            modelDescriptorPath = desired
            emitUIAction(level: .info, message: "Model descriptor set for task", action: "descriptorAutoSet", metadata: [
                "reason": reason,
                "path": desired
            ])
            return resolvedDescriptorPath()
        }

        if taskMode == .singleLift && isQuadDescriptorPath(trimmed) {
            modelDescriptorPath = desired
            emitUIAction(level: .warning, message: "Model descriptor auto-switched for Single Lift task", action: "descriptorAutoSwitch", metadata: [
                "reason": reason,
                "from": trimmed,
                "to": desired
            ])
        } else if taskMode != .singleLift && isSinglePropDescriptorPath(trimmed) {
            modelDescriptorPath = desired
            emitUIAction(level: .warning, message: "Model descriptor auto-switched for quad task", action: "descriptorAutoSwitch", metadata: [
                "reason": reason,
                "from": trimmed,
                "to": desired
            ])
        }

        return resolvedDescriptorPath()
    }

    private func emitObjectiveWarningIfNeeded() {
        if taskMode != .singleLift {
            emitUIAction(level: .warning, message: "Objective mismatch: expected Single Lift task", action: "objectiveMismatch", metadata: [
                "expected": SimulationTaskMode.singleLift.rawValue
            ])
        }
    }

    private func emitManualActuatorUpdate(reason: String) {
        let now = Date().timeIntervalSinceReferenceDate
        let delta = zip(manualActuatorValues, lastManualActuatorLoggedValues)
            .map { abs($0 - $1) }
            .max() ?? 0.0
        let shouldLog = (now - lastManualActuatorLogTime) >= 0.5 || delta >= 0.02
        guard shouldLog else { return }
        lastManualActuatorLogTime = now
        lastManualActuatorLoggedValues = manualActuatorValues
        emitUIAction(level: .info, message: "Manual actuator values updated", action: "manualActuatorUpdate", metadata: [
            "reason": reason,
            "enabled": "\(manualActuatorEnabled)",
            "linked": "\(manualActuatorLinked)",
            "valuesNormalized": manualActuatorValues.map { String(format: "%.3f", $0) }.joined(separator: ","),
            "valuesPhysical": manualActuatorValues.indices
                .map { String(format: "%.3f", manualActuatorValuePhysical(index: $0)) }
                .joined(separator: ",")
        ])
    }

    func createModel(named name: String? = nil) {
        let nextIndex = availableModels.count + 1
        let modelName = (name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Model \(nextIndex)"
        let modelID = UUID()
        let info = TrainingModelInfo(
            id: modelID,
            name: modelName,
            createdAt: Date(),
            lastTrainedAt: nil,
            hasSupervisedBootstrap: false,
            storageURL: modelDirectory(for: modelID)
        )
        let store = ManasMLXModelStore()
        let command = CommandSystem(modelStore: store)
        command.setManualActuatorStore(manualActuatorStore)
        let loop = TrainingLoopController(modelStore: store)
        let telemetry: (WorldStepLog) -> Void = { [weak self] step in
            self?.recordLiveStep(step)
        }
        command.setTelemetry(telemetry)
        loop.setTelemetry(telemetry)
        modelContexts[info.id] = ModelContext(
            store: store,
            commandSystem: command,
            trainingLoopController: loop
        )
        availableModels.append(info)
        selectModel(id: info.id)
        emitUIAction(level: .info, message: "Model created", action: "createModel", metadata: [
            "name": modelName
        ])
    }

    func selectModel(id: UUID?) {
        guard let id else { return }
        if isRunning || isTraining || isLoopRunning {
            emitUIAction(level: .warning, message: "Stop training before switching models", action: "selectModel")
            selectedModelID = activeModelID
            return
        }
        guard let context = modelContexts[id] else {
            emitUIAction(level: .warning, message: "Model context not found", action: "selectModel")
            return
        }
        selectedModelID = id
        activeModelID = id
        modelStore = context.store
        commandSystem = context.commandSystem
        trainingLoopController = context.trainingLoopController
        loadSelectedModelIfAvailable()
        emitUIAction(level: .info, message: "Model selected", action: "selectModel", metadata: [
            "modelId": id.uuidString,
            "name": selectedModel?.name ?? "unknown"
        ])
    }

    func clearTrainingState() {
        guard let selectedModelID else { return }
        if isRunning || isTraining || isLoopRunning {
            emitUIAction(level: .warning, message: "Stop training before clearing", action: "clearTrainingState")
            return
        }
        activeModelID = selectedModelID
        if let selectedModel = selectedModel {
            removeModelArtifacts(at: selectedModel.storageURL)
        }
        let store = ManasMLXModelStore()
        let command = CommandSystem(modelStore: store)
        command.setManualActuatorStore(manualActuatorStore)
        let loop = TrainingLoopController(modelStore: store)
        let telemetry: (WorldStepLog) -> Void = { [weak self] step in
            self?.recordLiveStep(step)
        }
        command.setTelemetry(telemetry)
        loop.setTelemetry(telemetry)
        modelContexts[selectedModelID] = ModelContext(
            store: store,
            commandSystem: command,
            trainingLoopController: loop
        )
        modelStore = store
        commandSystem = command
        trainingLoopController = loop
        updateSelectedModel { model in
            model.hasSupervisedBootstrap = false
            model.lastTrainedAt = nil
        }
        clearRuns()
        lastTrainingLoss = nil
        loopBestScore = nil
        loopLastScore = nil
        loopStatusMessage = "Cleared"
        trainingLossSamples.removeAll()
        loopScoreSamples.removeAll()
        overshootSamples.removeAll()
        recoverySamples.removeAll()
        hfSamples.removeAll()
        emitUIAction(level: .notice, message: "Training state cleared", action: "clearTrainingState")
    }

    func runBaseline() {
        guard !isRunning, !isLoopRunning else {
            emitUIAction(level: .warning, message: "Run already in progress", action: "runBaseline")
            return
        }
        resetLiveStride()
        if taskMode != .singleLift {
            emitUIAction(level: .warning, message: "Run auto-switched to Single Lift task", action: "runBaseline", metadata: [
                "fromTask": taskMode.rawValue,
                "toTask": SimulationTaskMode.singleLift.rawValue,
                "reason": "baselineRequiresSingleLift"
            ])
            taskMode = .singleLift
        }
        let resolvedPath = ensureDescriptorForTask(reason: "runBaseline")
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

        let effectiveController: ControllerSelection
        if manualActuatorEnabled {
            if controllerSelection != .baseline {
                emitUIAction(level: .warning, message: "Manual actuators force baseline controller", action: "runBaseline", metadata: [
                    "reason": "manualActuatorEnabled"
                ])
            }
            effectiveController = .baseline
        } else {
            effectiveController = controllerSelection
        }

        let request = SimulationRunRequest(
            controller: effectiveController,
            taskMode: taskMode,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            modelDescriptorPath: resolvedPath,
            overrideParameters: preflightParameters(modelPath: resolvedPath),
            useAux: trainingUseAux,
            useQualityGating: trainingUseQualityGating
        )
        activeParameters = request.overrideParameters

        emitUIAction(
            level: .notice,
            message: "Run started (single)",
            action: "runBaseline",
            metadata: [
                "controller": controllerSelection.rawValue,
                "tier": "\(determinism.tier)",
                "cutPeriod": "\(cutPeriodSteps)"
            ]
        )
        emitObjectiveWarningIfNeeded()
        emitTaskMismatchWarnings(modelPath: resolvedPath)

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
                        self.emitScenarioFailures(output: record.output)
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
            do {
                _ = try await commandSystem.submit(.pause)
                isPaused.toggle()
                let message = isPaused ? "Paused" : "Resumed"
                emitUIAction(level: .notice, message: message, action: "pauseRun")
            } catch {
                emitUIAction(level: .error, message: "Pause command failed", action: "pauseRun", metadata: [
                    "error": "\(error)"
                ])
            }
        }
    }

    func stopRun() {
        Task {
            do {
                _ = try await commandSystem.submit(.stop)
                isPaused = false
                emitUIAction(level: .notice, message: "Stop requested", action: "stopRun")
            } catch {
                emitUIAction(level: .error, message: "Stop command failed", action: "stopRun", metadata: [
                    "error": "\(error)"
                ])
            }
        }
    }

    func exportLogs() {
        guard let run = selectedRun else { return }
        let trimmed = logDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            emitUIAction(level: .error, message: "Log directory is empty", action: "exportLogs")
            return
        }
        let url = URL(fileURLWithPath: trimmed, isDirectory: true)
        Task {
            do {
                let result = try await commandSystem.submit(.exportLogs(output: run.output, directory: url))
                if case .logsExported(let bundle) = result {
                    emitUIAction(
                        level: .info,
                        message: "Logs exported",
                        action: "exportLogs",
                        metadata: [
                            "path": "\(url.path)",
                            "count": "\(bundle.logs.count)"
                        ]
                    )
                }
            } catch {
                emitUIAction(level: .error, message: "Export failed: \(error)", action: "exportLogs")
            }
        }
    }

    func exportTrainingDataset() {
        guard let run = selectedRun else {
            emitUIAction(level: .error, message: "No run selected", action: "exportDataset")
            return
        }
        let trimmed = trainingDatasetDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            emitUIAction(level: .error, message: "Training dataset directory is empty", action: "exportDataset")
            return
        }

        let url = URL(fileURLWithPath: trimmed, isDirectory: true)
        Task {
            do {
                let result = try await commandSystem.submit(.exportDataset(output: run.output, directory: url))
                if case .datasetExported(let count) = result {
                    emitUIAction(
                        level: .info,
                        message: "Training dataset exported",
                        action: "exportDataset",
                        metadata: [
                            "path": "\(url.path)",
                            "count": "\(count)"
                        ]
                    )
                }
            } catch {
                emitUIAction(level: .error, message: "Training dataset export failed: \(error)", action: "exportDataset")
            }
        }
    }

    func runTraining() {
        guard !isRunning, !isTraining, !isLoopRunning else {
            emitUIAction(level: .warning, message: "Training already in progress", action: "runTraining")
            return
        }
        emitUIAction(level: .notice, message: "Training requested", action: "runTraining")
        if selectedModel?.hasSupervisedBootstrap == true {
            startTrainingLoop()
            return
        }
        if let url = resolvedTrainingInputURL(), trainingDatasetExists(at: url) {
            trainCoreModel(thenStartLoop: true)
        } else {
            startTrainingLoop()
        }
    }

    func trainCoreModel(thenStartLoop: Bool = false) {
        guard !isTraining else {
            emitUIAction(level: .warning, message: "Training already in progress", action: "trainCoreModel")
            return
        }
        guard let url = resolvedTrainingInputURL() else { return }
        isTraining = true
        lastTrainingLoss = nil

        emitUIAction(level: .notice, message: "Training started", action: "trainCoreModel", metadata: [
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
                let sampleIndex = Double(trainingLossSamples.count + 1)
                trainingLossSamples.append(MetricSample(time: sampleIndex, value: output.finalLoss))
                updateSelectedModel { model in
                    model.hasSupervisedBootstrap = true
                    model.lastTrainedAt = Date()
                }
                persistSelectedModel()
                emitUIAction(level: .info, message: "Training completed", action: "trainCoreModel", metadata: [
                    "finalLoss": String(format: "%.6f", output.finalLoss),
                    "epochs": "\(output.epochs)"
                ])
                if thenStartLoop {
                    startTrainingLoop()
                }
            } catch {
                isTraining = false
                emitError("Training failed", error: error)
            }
        }
    }

    func startTrainingLoop() {
        guard !isLoopRunning, !isRunning else {
            emitUIAction(level: .warning, message: "Loop already running", action: "startTrainingLoop")
            return
        }
        resetLiveStride()
        if taskMode != .singleLift {
            emitUIAction(level: .warning, message: "Training loop auto-switched to Single Lift task", action: "startTrainingLoop", metadata: [
                "fromTask": taskMode.rawValue,
                "toTask": SimulationTaskMode.singleLift.rawValue,
                "reason": "loopRequiresSingleLift"
            ])
            taskMode = .singleLift
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

        let isPreview = isPreviewEnvironment
        let loopController: ControllerSelection
        if controllerSelection == .manasMLX {
            loopController = controllerSelection
        } else {
            loopController = .manasMLX
            emitUIAction(level: .warning, message: "Training loop forces ManasMLX controller", action: "startTrainingLoop", metadata: [
                "from": controllerSelection.rawValue,
                "to": ControllerSelection.manasMLX.rawValue,
                "reason": "loopRequiresManasMLX"
            ])
        }

        let resolvedPath = ensureDescriptorForTask(reason: "startTrainingLoop")
        let runRequest = SimulationRunRequest(
            controller: loopController,
            taskMode: taskMode,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            modelDescriptorPath: resolvedPath,
            overrideParameters: preflightParameters(modelPath: resolvedPath),
            useAux: trainingUseAux,
            useQualityGating: trainingUseQualityGating
        )
        activeParameters = runRequest.overrideParameters

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
            allowAutoBackoff: loopAllowAutoBackoff,
            enableDatasetExport: true,
            enableTraining: true
        )

        activeLoopController = loopController
        isLoopRunning = true
        isLoopPaused = false
        loopIteration = 0
        loopBestScore = nil
        loopLastScore = nil
        loopStatusMessage = "Loop started"
        loopScoreSamples.removeAll()
        overshootSamples.removeAll()
        recoverySamples.removeAll()
        hfSamples.removeAll()
        emitUIAction(level: .notice, message: "Training loop started", action: "startTrainingLoop", metadata: [
            "controller": loopController.rawValue,
            "iterations": "\(loopMaxIterations)",
            "evalInterval": "\(loopEvaluationInterval)",
            "stopOnPass": loopStopOnPass ? "true" : "false"
        ])
        emitObjectiveWarningIfNeeded()
        emitTaskMismatchWarnings(modelPath: resolvedPath)
        if isPreview {
            emitUIAction(level: .warning, message: "Preview loop uses full training settings; export disabled", action: "startTrainingLoop", metadata: [
                "reason": "previewMode"
            ])
        }
        emitUIAction(level: .notice, message: "Training config", action: "startTrainingLoop", metadata: [
            "sequence": "\(trainingSequenceLength)",
            "epochs": "\(trainingEpochs)",
            "lr": String(format: "%.6f", trainingLearningRate),
            "aux": trainingUseAux ? "true" : "false",
            "qualityGate": trainingUseQualityGating ? "true" : "false",
            "hoverThrustScale": String(format: "%.3f", hoverThrustScale)
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
                emitUIAction(level: .notice, message: "Training loop paused", action: "pauseTrainingLoop", metadata: [
                    "controller": activeLoopController?.rawValue ?? controllerSelection.rawValue
                ])
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
                emitUIAction(level: .notice, message: "Training loop resumed", action: "resumeTrainingLoop", metadata: [
                    "controller": activeLoopController?.rawValue ?? controllerSelection.rawValue
                ])
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
                emitUIAction(level: .notice, message: "Training loop stop requested", action: "stopTrainingLoop", metadata: [
                    "controller": activeLoopController?.rawValue ?? controllerSelection.rawValue
                ])
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
        case .teacherRunStarted(let iteration, let hoverThrustScale):
            emitTerminal(level: .notice, message: "Teacher run started", metadata: [
                "iter": "\(iteration)",
                "controller": "baseline",
                "task": taskMode.rawValue,
                "hoverThrustScale": String(format: "%.3f", hoverThrustScale)
            ])
        case .teacherRunCompleted(let iteration, let output):
            emitTerminal(level: .notice, message: "Teacher run completed", metadata: [
                "iter": "\(iteration)",
                "passed": "\(output.summary.suitePassed)",
                "scenarios": "\(output.logs.count)"
            ])
        case .runCompleted(let iteration, let output, let score):
            loopIteration = iteration
            loopLastScore = score
            if loopBestScore == nil || score > (loopBestScore ?? -Double.greatestFiniteMagnitude) {
                loopBestScore = score
            }
            let iterationTime = Double(iteration)
            loopScoreSamples.append(MetricSample(time: iterationTime, value: score))
            let record = Self.buildRunRecord(output: output)
            runs.insert(record, at: 0)
            selectedRunID = record.id
            selectedScenarioKey = record.scenarios.first?.id
            if !output.summary.suitePassed {
                emitScenarioFailures(output: output)
            }
            let aggregate = output.summary.aggregate
            let overshoot = aggregate.worstOvershootDegrees.map { String(format: "%.2f", $0) } ?? "n/a"
            let recovery = aggregate.averageRecoveryTime.map { String(format: "%.2f", $0) } ?? "n/a"
            let hf = aggregate.averageHfStabilityScore.map { String(format: "%.2f", $0) } ?? "n/a"
            if let value = aggregate.worstOvershootDegrees {
                overshootSamples.append(MetricSample(time: iterationTime, value: value))
            }
            if let value = aggregate.averageRecoveryTime {
                recoverySamples.append(MetricSample(time: iterationTime, value: value))
            }
            if let value = aggregate.averageHfStabilityScore {
                hfSamples.append(MetricSample(time: iterationTime, value: value))
            }
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
            updateSelectedModel { model in
                model.hasSupervisedBootstrap = true
                model.lastTrainedAt = Date()
            }
            persistSelectedModel()
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
            activeLoopController = nil
        case .completed(let summary):
            isLoopRunning = false
            isLoopPaused = false
            activeLoopController = nil
            loopBestScore = summary.bestScore
            loopLastScore = summary.lastScore
            loopStatusMessage = summary.passed ? "Completed (passed)" : "Completed"
            emitTerminal(level: .info, message: "Training loop completed", metadata: [
                "iterations": "\(summary.iterations)",
                "bestScore": String(format: "%.3f", summary.bestScore)
            ])
        case .failed(let message):
            loopStatusMessage = "Failed"
            activeLoopController = nil
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
        descriptorCachePath = nil
        descriptorCache = nil
        descriptorCacheError = nil
        refreshManualActuatorLayout()
        emitUIAction(level: .info, message: "Model descriptor set", action: "setDescriptorPath", metadata: [
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

    private func resolvedDescriptorPathForCache() -> String {
        KuyuUIModelPaths.resolveDescriptorPath(modelDescriptorPath)
    }

    private func resolvedDescriptorPath() -> String {
        let resolved = resolvedDescriptorPathForCache()
        if resolved != modelDescriptorPath {
            let previous = modelDescriptorPath
            modelDescriptorPath = resolved
            emitUIAction(level: .warning, message: "Model descriptor not found, using fallback", action: "descriptorFallback", metadata: [
                "from": previous,
                "to": resolved,
                "reason": "notFound"
            ])
        }
        return resolved
    }

    private func descriptorSnapshot() -> LoadedRobotDescriptor? {
        let resolved = resolvedDescriptorPathForCache().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolved.isEmpty else {
            descriptorCachePath = nil
            descriptorCache = nil
            descriptorCacheError = nil
            return nil
        }

        if descriptorCachePath == resolved {
            return descriptorCache
        }

        descriptorCachePath = resolved
        do {
            let loader = RobotDescriptorLoader()
            let loaded = try loader.loadDescriptor(path: resolved)
            descriptorCache = loaded
            descriptorCacheError = nil
            refreshManualActuatorLayout()
            return loaded
        } catch {
            descriptorCache = nil
            descriptorCacheError = "\(error)"
            refreshManualActuatorLayout()
            return nil
        }
    }

    private func refreshManualActuatorLayout() {
        let targetCount = expectedManualActuatorChannelCount()
        manualActuatorStore.configure(channelCount: targetCount)
        guard manualActuatorValues.count != targetCount else { return }

        let baseline = min(max(manualActuatorValues.first ?? manualActuatorMaster, 0.0), 1.0)
        manualActuatorValues = Array(repeating: baseline, count: targetCount)
        lastManualActuatorLoggedValues = manualActuatorValues
    }

    private func expectedManualActuatorChannelCount() -> Int {
        let defaultCount = taskMode == .singleLift ? 1 : 4
        if let descriptor = descriptorCache?.descriptor {
            let count = descriptor.signals.actuator.count
            if count == defaultCount {
                return count
            }
        }
        return defaultCount
    }

    private func currentMotorNerveProfile() -> String {
        let fallback = taskMode == .singleLift ? "fixed-single-prop" : "fixed-quad"
        guard let descriptor = descriptorSnapshot()?.descriptor else { return fallback }
        let expectedDriveCount = taskMode == .singleLift ? 1 : 4
        if descriptor.control.driveChannels.count != expectedDriveCount {
            return fallback
        }
        if descriptor.motorNerve.stages.contains(where: { $0.type == .custom }) {
            return fallback
        }
        return "descriptor-chain"
    }

    private func preflightParameters(modelPath: String) -> ReferenceQuadrotorParameters? {
        let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        do {
            let loader = RobotDescriptorLoader()
            let loaded = try loader.loadDescriptor(path: trimmed)
            let inertial = try loader.loadPlantInertialProperties(descriptor: loaded)
            let parameters = try ReferenceQuadrotorParameters.reference(
                from: inertial,
                robotID: loaded.descriptor.robot.robotID
            )
            emitUIAction(level: .info, message: "Model loaded", action: "modelPreflight", metadata: [
                "path": trimmed
            ])
            return parameters
        } catch {
            emitUIAction(level: .warning, message: "Model load failed, using baseline", action: "modelPreflight", metadata: [
                "path": trimmed,
                "reason": "loadFailed",
                "error": "\(error)"
            ])
            return ReferenceQuadrotorParameters.baseline
        }
    }

    private func preflightParameters() -> ReferenceQuadrotorParameters? {
        preflightParameters(modelPath: resolvedDescriptorPath())
    }

    private func resolvedTrainingInputURL() -> URL? {
        let trimmed = trainingInputDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            emitError("Training dataset directory is empty")
            return nil
        }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    private func trainingDatasetExists(at root: URL) -> Bool {
        let fileManager = FileManager.default
        let metaURL = root.appendingPathComponent("meta.json")
        let recordsURL = root.appendingPathComponent("records.jsonl")
        if fileManager.fileExists(atPath: metaURL.path),
           fileManager.fileExists(atPath: recordsURL.path) {
            return true
        }
        let items: [URL]
        do {
            items = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        } catch {
            return false
        }
        for url in items {
            let meta = url.appendingPathComponent("meta.json")
            let records = url.appendingPathComponent("records.jsonl")
            if fileManager.fileExists(atPath: meta.path),
               fileManager.fileExists(atPath: records.path) {
                return true
            }
        }
        return false
    }

    private func loadPersistedModelsOrFallback(defaultStore: ManasMLXModelStore) {
        let persisted = loadPersistedModels()
        if persisted.isEmpty {
            let defaultID = UUID()
            let info = TrainingModelInfo(
                id: defaultID,
                name: "Default",
                createdAt: Date(),
                lastTrainedAt: nil,
                hasSupervisedBootstrap: false,
                storageURL: modelDirectory(for: defaultID)
            )
            availableModels = [info]
            activeModelID = info.id
            selectedModelID = info.id
            modelContexts[info.id] = ModelContext(
                store: defaultStore,
                commandSystem: commandSystem,
                trainingLoopController: trainingLoopController
            )
            return
        }

        availableModels = persisted
        modelContexts.removeAll()
        for model in persisted {
            let store = ManasMLXModelStore()
            let command = CommandSystem(modelStore: store)
            command.setManualActuatorStore(manualActuatorStore)
            let loop = TrainingLoopController(modelStore: store)
            let telemetry: (WorldStepLog) -> Void = { [weak self] step in
                self?.recordLiveStep(step)
            }
            command.setTelemetry(telemetry)
            loop.setTelemetry(telemetry)
            modelContexts[model.id] = ModelContext(
                store: store,
                commandSystem: command,
                trainingLoopController: loop
            )
        }

        if let first = persisted.first, let context = modelContexts[first.id] {
            selectedModelID = first.id
            activeModelID = first.id
            modelStore = context.store
            commandSystem = context.commandSystem
            trainingLoopController = context.trainingLoopController
            loadSelectedModelIfAvailable()
        }
    }

    private func loadPersistedModels() -> [TrainingModelInfo] {
        let root = modelRootDirectory()
        let fileManager = FileManager.default
        let directories: [URL]
        do {
            directories = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var models: [TrainingModelInfo] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for url in directories {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: [.isDirectoryKey])
            } catch {
                continue
            }
            guard values.isDirectory == true else { continue }
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            let manifestURL = url.appendingPathComponent("model.json")
            let data: Data
            do {
                data = try Data(contentsOf: manifestURL)
            } catch {
                continue
            }
            let manifest: ManasMLXModelManifest
            do {
                manifest = try decoder.decode(ManasMLXModelManifest.self, from: data)
            } catch {
                continue
            }

            let hasWeights = fileManager.fileExists(atPath: url.appendingPathComponent("core.safetensors").path)
            let info = TrainingModelInfo(
                id: id,
                name: manifest.name,
                createdAt: manifest.createdAt,
                lastTrainedAt: manifest.lastTrainedAt,
                hasSupervisedBootstrap: hasWeights,
                storageURL: url
            )
            models.append(info)
        }

        return models.sorted { $0.createdAt < $1.createdAt }
    }

    private func loadSelectedModelIfAvailable() {
        guard let selectedModel else { return }
        let manifestURL = selectedModel.storageURL.appendingPathComponent("model.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }
        do {
            let manifest = try modelStore.loadModel(from: selectedModel.storageURL)
            updateSelectedModel { model in
                model.name = manifest.name
                model.createdAt = manifest.createdAt
                model.lastTrainedAt = manifest.lastTrainedAt
                model.hasSupervisedBootstrap = true
            }
            emitTerminal(level: .info, message: "Model loaded", metadata: [
                "name": manifest.name,
                "path": selectedModel.storageURL.path
            ])
        } catch {
            emitError("Model load failed", error: error)
        }
    }

    private func persistSelectedModel() {
        guard let selectedModel else { return }
        guard let coreConfig = modelStore.currentCoreConfig else {
            emitTerminal(level: .warning, message: "Model configs unavailable; skip save")
            return
        }

        let manifest = ManasMLXModelManifest(
            name: selectedModel.name,
            createdAt: selectedModel.createdAt,
            lastTrainedAt: selectedModel.lastTrainedAt,
            coreConfig: coreConfig,
            reflexConfig: modelStore.currentReflexConfig
        )
        do {
            try modelStore.saveModel(to: selectedModel.storageURL, manifest: manifest)
            emitTerminal(level: .info, message: "Model saved", metadata: [
                "path": selectedModel.storageURL.path
            ])
        } catch {
            emitError("Model save failed", error: error)
        }
    }

    private func removeModelArtifacts(at url: URL) {
        let fileManager = FileManager.default
        let artifacts = [
            url.appendingPathComponent("core.safetensors"),
            url.appendingPathComponent("reflex.safetensors"),
            url.appendingPathComponent("model.json")
        ]
        for artifact in artifacts where fileManager.fileExists(atPath: artifact.path) {
            do {
                try fileManager.removeItem(at: artifact)
            } catch {
                emitTerminal(level: .warning, message: "Failed to remove model artifact", metadata: [
                    "path": artifact.path,
                    "error": "\(error)"
                ])
            }
        }
    }

    private func modelRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Kuyu", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private func modelDirectory(for id: UUID) -> URL {
        modelRootDirectory().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func emitTerminal(
        level: Logger.Level,
        message: String,
        metadata: [String: String] = [:],
        label: String? = nil
    ) {
        let entry = UILogEntry(
            timestamp: Date(),
            level: level,
            label: label ?? logLabel,
            message: message,
            metadata: metadata
        )
        logStore.emit(entry)
    }

    func emitUIAction(
        level: Logger.Level,
        message: String,
        action: String,
        metadata: [String: String] = [:]
    ) {
        emitTerminal(
            level: level,
            message: message,
            metadata: uiActionMetadata(action: action, extra: metadata),
            label: "kuyu.ui"
        )
    }

    private func uiActionMetadata(action: String, extra: [String: String]) -> [String: String] {
        var metadata = extra
        metadata["action"] = action
        metadata["task"] = taskMode.rawValue
        metadata["model"] = selectedModel?.name ?? "default"
        metadata["modelDescriptor"] = resolvedDescriptorPathForCache()

        let profileMeta = taskProfileMetadata()
        for (key, value) in profileMeta {
            metadata[key] = value
        }

        if let descriptor = descriptorSnapshot()?.descriptor {
            metadata["robotID"] = descriptor.robot.robotID
        }
        return metadata
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

    private func emitScenarioFailures(output: KuyAtt1RunOutput) {
        for entry in output.logs {
            guard let reason = entry.log.failureReason else { continue }
            emitTerminal(level: .warning, message: "Scenario failed", metadata: [
                "scenario": entry.log.scenarioId.rawValue,
                "seed": "\(entry.log.seed.rawValue)",
                "reason": reason.rawValue,
                "time": String(format: "%.2f", entry.log.failureTime ?? 0)
            ])
        }
    }

    func sceneState(at time: Double) -> SceneState? {
        guard let scenario = selectedScenario else { return nil }
        return renderSystem.sceneState(for: scenario.log, time: time)
    }

    func currentSceneState(at time: Double) -> SceneState? {
        if (isRunning || isLoopRunning), let liveScene {
            return liveScene
        }
        return sceneState(at: time)
    }

    private func recordLiveStep(_ step: WorldStepLog) {
        updateLiveStrideIfNeeded(step)
        let stride = autoStridePending ? 1 : max(1, liveSampleStride)
        if (step.time.stepIndex % UInt64(stride)) != 0 { return }
        lastSensorSamples = step.sensorSamples
        lastActuatorValues = step.actuatorValues
        lastDriveIntents = step.driveIntents
        lastReflexCorrections = step.reflexCorrections
        lastActuatorTelemetry = step.actuatorTelemetry
        lastMotorNerveTrace = step.motorNerveTrace
        let root = step.plantState.root
        let body = BodySceneState(
            id: root.id,
            position: root.position,
            velocity: root.velocity,
            orientation: root.orientation,
            angularVelocity: root.angularVelocity
        )
        liveScene = SceneState(time: step.time.time, bodies: [body])

        if isRunning || isLoopRunning || isTraining {
            let now = step.time.time
            let last = lastTelemetryLogTime ?? -Double.greatestFiniteMagnitude
            if now - last >= 1.0 {
                lastTelemetryLogTime = now
                var metadata: [String: String] = [
                    "action": "telemetryStep",
                    "task": taskMode.rawValue,
                    "t": String(format: "%.2f", now),
                    "step": "\(step.time.stepIndex)",
                    "pos": String(format: "%.2f,%.2f,%.2f", root.position.x, root.position.y, root.position.z),
                    "vel": String(format: "%.2f,%.2f,%.2f", root.velocity.x, root.velocity.y, root.velocity.z)
                ]

                if taskMode == .singleLift {
                    let accelZ = step.sensorSamples.first(where: { $0.channelIndex == 5 })?.value
                    let drive = step.driveIntents.first?.activation
                    let uRaw = step.motorNerveTrace?.uRaw.first
                    let uOut = step.motorNerveTrace?.uOut.first
                    if let parameters = activeParameters {
                        let disturbanceZ = step.disturbances.forceWorld.z
                        let thrust = step.actuatorTelemetry.value(for: "motor1") ?? 0
                        let netAccelZ = (thrust + disturbanceZ) / parameters.mass - parameters.gravity
                        metadata["netAccelZ"] = String(format: "%.3f", netAccelZ)
                        metadata["gravity"] = String(format: "%.3f", parameters.gravity)
                        metadata["mass"] = String(format: "%.3f", parameters.mass)
                        if let uOut {
                            let expectedThrust = uOut * parameters.maxThrust
                            let thrustError = thrust - expectedThrust
                            metadata["u_out_thrust"] = String(format: "%.3f", expectedThrust)
                            metadata["thrustError"] = String(format: "%.3f", thrustError)
                        } else {
                            metadata["u_out_thrust"] = "n/a"
                            metadata["thrustError"] = "n/a"
                        }
                    }
                    metadata["accelZ"] = accelZ.map { String(format: "%.3f", $0) } ?? "n/a"
                    metadata["drive"] = drive.map { String(format: "%.3f", $0) } ?? "n/a"
                    metadata["u_raw"] = uRaw.map { String(format: "%.3f", $0) } ?? "n/a"
                    metadata["u_out"] = uOut.map { String(format: "%.3f", $0) } ?? "n/a"
                    let thrust = step.actuatorTelemetry.value(for: "motor1") ?? 0
                    metadata["thrust"] = String(format: "%.3f", thrust)
                }

                emitTerminal(level: .notice, message: "Sim step", metadata: metadata)
            }
        }
    }

    private func resetLiveStride() {
        autoStridePending = true
        lastLiveStepTime = nil
    }

    private func updateLiveStrideIfNeeded(_ step: WorldStepLog) {
        guard autoStridePending else { return }
        if let last = lastLiveStepTime {
            let dt = step.time.time - last
            if dt > 0 {
                let desiredStride = max(1, Int(round((1.0 / targetRenderFPS) / dt)))
                liveSampleStride = desiredStride
                autoStridePending = false
                emitTerminal(level: .info, message: "Render stride auto-set", metadata: [
                    "action": "renderStrideAuto",
                    "task": taskMode.rawValue,
                    "dt": String(format: "%.4f", dt),
                    "stride": "\(desiredStride)",
                    "targetFps": String(format: "%.1f", targetRenderFPS)
                ])
            }
        }
        lastLiveStepTime = step.time.time
    }

    func renderAssetInfo() -> RenderAssetInfo? {
        guard useRenderAssets else { return nil }
        guard let loaded = descriptorSnapshot() else { return nil }
        let loader = RobotDescriptorLoader()
        guard let asset = loader.primaryRenderAsset(descriptor: loaded) else { return nil }
        let url = loader.loadRenderURL(asset: asset, baseURL: loaded.baseURL)
        return RenderAssetInfo(
            name: asset.name,
            url: url,
            format: asset.format
        )
    }

    func currentDescriptor() -> RobotDescriptor? {
        descriptorSnapshot()?.descriptor
    }

    func currentDescriptorError() -> String? {
        _ = descriptorSnapshot()
        return descriptorCacheError
    }

    func motorNerveStages() -> [RobotDescriptor.MotorNerveStage] {
        descriptorSnapshot()?.descriptor.motorNerve.stages ?? []
    }

    func driveSignalDefinitions() -> [RobotDescriptor.SignalDefinition] {
        guard let descriptor = descriptorSnapshot()?.descriptor else { return [] }
        return orderedSignals(ids: descriptor.control.driveChannels, from: descriptor.signals.drive)
    }

    func reflexSignalDefinitions() -> [RobotDescriptor.SignalDefinition] {
        guard let descriptor = descriptorSnapshot()?.descriptor else { return [] }
        return orderedSignals(ids: descriptor.control.reflexChannels, from: descriptor.signals.reflex)
    }

    func actuatorSignalDefinitions() -> [RobotDescriptor.SignalDefinition] {
        let definitions = descriptorSnapshot()?.descriptor.signals.actuator ?? []
        return definitions.sorted { $0.index < $1.index }
    }

    func motorNerveSignalDefinitions() -> [RobotDescriptor.SignalDefinition] {
        descriptorSnapshot()?.descriptor.signals.motorNerve ?? []
    }

    func manualActuatorChannelLabels() -> [String] {
        let definitions = actuatorSignalDefinitions()
        if definitions.isEmpty {
            return manualActuatorValues.indices.map { "A\($0)" }
        }

        return manualActuatorValues.indices.map { index in
            if index < definitions.count {
                return definitions[index].name
            }
            return "A\(index)"
        }
    }

    func manualActuatorChannelUnit(index: Int) -> String {
        let definitions = actuatorSignalDefinitions()
        guard index >= 0, index < definitions.count else { return "" }
        return definitions[index].units
    }

    func manualActuatorChannelRanges() -> [ClosedRange<Double>] {
        let channelCount = max(manualActuatorValues.count, 1)
        let fallbackUpper = defaultManualActuatorUpperBound()
        var ranges = Array(repeating: (0.0...fallbackUpper), count: channelCount)

        guard let descriptor = descriptorCache?.descriptor else {
            return ranges
        }

        let sortedSignals = descriptor.signals.actuator.sorted { $0.index < $1.index }
        var limitsBySignalID: [String: ClosedRange<Double>] = [:]
        for actuator in descriptor.actuators {
            for channelID in actuator.channels {
                let minValue = actuator.limits.min
                let maxValue = actuator.limits.max
                if let existing = limitsBySignalID[channelID] {
                    limitsBySignalID[channelID] = min(existing.lowerBound, minValue)...max(existing.upperBound, maxValue)
                } else {
                    limitsBySignalID[channelID] = minValue...maxValue
                }
            }
        }

        let count = min(channelCount, sortedSignals.count)
        for index in 0..<count {
            let signal = sortedSignals[index]
            if let limits = limitsBySignalID[signal.id] {
                ranges[index] = normalizedClosedRange(min: limits.lowerBound, max: limits.upperBound, fallbackUpper: fallbackUpper)
                continue
            }
            if let range = signal.range {
                ranges[index] = normalizedClosedRange(min: range.min, max: range.max, fallbackUpper: fallbackUpper)
            }
        }

        return ranges
    }

    private func defaultManualActuatorUpperBound() -> Double {
        if let parameters = activeParameters {
            return max(parameters.maxThrust, 1.0)
        }
        return max(ReferenceQuadrotorParameters.baseline.maxThrust, 1.0)
    }

    private func normalizedClosedRange(min minValue: Double, max maxValue: Double, fallbackUpper: Double) -> ClosedRange<Double> {
        if maxValue > minValue {
            return minValue...maxValue
        }
        let fallbackMax = max(fallbackUpper, minValue + 1.0)
        return minValue...fallbackMax
    }

    private func orderedSignals(
        ids: [String],
        from definitions: [RobotDescriptor.SignalDefinition]
    ) -> [RobotDescriptor.SignalDefinition] {
        let map = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        return ids.compactMap { map[$0] }
    }

}
