import Configuration
import Foundation
import Logging
import Observation
import KuyuCore
import KuyuMLX
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

@Observable
@MainActor
public final class SimulationViewModel {
    private struct ModelContext {
        let store: ManasMLXModelStore
        let commandSystem: CommandSystem
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
    private(set) var modelDescriptorPath: String = KuyuUIModelPaths.defaultDescriptorPath() {
        didSet {
            descriptorCachePath = nil
            descriptorCache = nil
            descriptorCacheError = nil
        }
    }
    var descendingVectorText: String = ""
    var descendingProgramText: String = ""
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
    var validationLossSamples: [MetricSample] = []
    var loopScoreSamples: [MetricSample] = []
    var rewardAverageSamples: [MetricSample] = []
    var passRateSamples: [MetricSample] = []
    var failureRateSamples: [MetricSample] = []
    var safetyViolationSamples: [MetricSample] = []
    var workerThroughputSamples: [MetricSample] = []
    var overshootSamples: [MetricSample] = []
    var recoverySamples: [MetricSample] = []
    var hfSamples: [MetricSample] = []
    var trainingLiveStatus: TrainingLiveStatus = .idle
    var trainingTimeline: [TrainingTimelineEntry] = []
    var lastTrainingRunArtifactDirectory: URL?
    var lastPostRegressionGate: PostRegressionGateState?
    var lastConvergenceSummary: ConvergenceSummary?
    var lastCheckpointDecision: CheckpointDecision?
    var learningCampaignExperimentName: String = "Kuyu Lift Training Plan"
    var learningCampaignExperimentDescription: String = "Hybrid GA/RL campaign for Manas checkpoint improvement"
    var learningCampaignTagsText: String = "navigation, hybrid, ppo, ga"
    var learningStrategySelection: LearningStrategySelection = .hybrid
    var learningCampaignArtifactDirectory: String = ""
    var learningCampaignSourceCheckpointPath: String = ""
    var learningCampaignSuites: String = "6"
    var learningCampaignSeedCount: Int = 1
    var learningCampaignPopulation: Int = 4
    var learningCampaignGenerations: Int = 1
    var learningCampaignEliteCount: Int = 1
    var learningCampaignWorkers: Int = 1
    var learningCampaignCandidateEvaluationConcurrency: Int = 1
    var learningCampaignEpisodes: Int = 1
    var learningCampaignMutationRate: Double = 0.08
    var learningCampaignMutationNoiseScale: Double = 0.01
    var learningCampaignMinimumIncumbentImprovement: Double = 0
    var learningCampaignAdaptiveMutation: Bool = false
    var learningCampaignCompactRetention: Bool = false
    var learningCampaignPreset: LearningCampaignRunPreset = .standard {
        didSet { applyLearningCampaignPreset(learningCampaignPreset) }
    }
    var learningCampaignReadiness: LearningCampaignReadinessState = .idle
    var learningCampaignLaunchEstimate: LearningCampaignLaunchEstimate?
    var learningCampaignTemplateStatus: String?
    var learningCampaignQueuedRuns: [LearningCampaignQueuedRun] = []
    var learningCampaignProgressFraction: Double = 0
    var learningCampaignCurrentPhase: String = "idle"
    var learningCampaignLatestEvent: String?
    var isLearningCampaignRunning = false
    var learningCampaignMonitorEnabled = false
    var learningCampaignState: LearningCampaignRunStoreState?
    var learningCampaignError: String?
    var simulationPlaybackFraction: Double = 0
    var simulationShowsTrajectoryOverlay = true
    var simulationShowsSensorReadouts = true
    var simulationShowsRewardEvents = true
    var reportExportStatus: String?

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
    private let checkpointStore = ModelCheckpointStore()
    private let trainingRunPresenter = TrainingRunPresenter()
    private let trainingRunStore = TrainingRunStore()
    private let regressionRunStore = RegressionRunStore()
    private let trainingRunCoordinator = TrainingRunCoordinator()
    private let trainingBootstrapCoordinator = TrainingBootstrapCoordinator()
    private let learningCampaignRunStore = LearningCampaignRunStore()
    private let trainingLoopReducer = TrainingLoopStateReducer()
    private let descendingIntentResolver = DescendingIntentResolver()
    private var telemetryPresenter = TelemetryPresenter()
    private var modelStore: ManasMLXModelStore
    private let manualActuatorStore = ManualActuatorStore()
    private var lastManualActuatorLogTime: TimeInterval = 0
    private var lastManualActuatorLoggedValues: [Double] = [0.0, 0.0, 0.0, 0.0]
    private var modelContexts: [UUID: ModelContext] = [:]
    private var logObserverInstalled = false
    private var learningCampaignMonitorTask: Task<Void, Never>?
    private var learningCampaignEventTask: Task<Void, Never>?
    private var learningCampaignWaitTask: Task<Void, Never>?
    private var learningCampaignHandle: LearningCampaignRunHandle?
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
        self.logger = Logger(label: "kuyu.ui")
        self.logger.logLevel = .info

        let telemetry: (WorldStepLog) -> Void = { [weak self] step in
            self?.recordLiveStep(step)
        }
        self.commandSystem.setTelemetry(telemetry)
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
        if taskMode == .singleLift && DescriptorSelection.isQuadDescriptorPath(modelPath) {
            emitUIAction(level: .warning, message: "Single Lift task using quad model descriptor", action: "taskDescriptorMismatch", metadata: [
                "path": modelPath,
                "reason": "singleLiftUsesQuad"
            ])
        }
        if taskMode != .singleLift && DescriptorSelection.isSinglePropDescriptorPath(modelPath) {
            emitUIAction(level: .warning, message: "Quad task using single-prop model descriptor", action: "taskDescriptorMismatch", metadata: [
                "path": modelPath,
                "reason": "quadUsesSingleProp"
            ])
        }
    }

    private func isQuadDescriptorPath(_ path: String) -> Bool {
        DescriptorSelection.isQuadDescriptorPath(path)
    }

    private func isSinglePropDescriptorPath(_ path: String) -> Bool {
        DescriptorSelection.isSinglePropDescriptorPath(path)
    }

    private func desiredDescriptorPath(for task: SimulationTaskMode) -> String {
        DescriptorSelection.desiredDescriptorPath(for: task)
    }

    private func ensureDescriptorForTask(reason: String) -> String {
        let resolution = DescriptorSelection.resolveForTask(
            configuredPath: modelDescriptorPath,
            taskMode: taskMode
        )
        if resolution.didSwitch && resolution.reason == "emptyPath" {
            modelDescriptorPath = resolution.path
            emitUIAction(level: .info, message: "Model descriptor set for task", action: "descriptorAutoSet", metadata: [
                "reason": reason,
                "path": resolution.path
            ])
            return resolvedDescriptorPath()
        }

        if resolution.didSwitch && resolution.reason == "singleLiftUsesQuad" {
            let previous = modelDescriptorPath.trimmingCharacters(in: .whitespacesAndNewlines)
            modelDescriptorPath = resolution.path
            emitUIAction(level: .warning, message: "Model descriptor auto-switched for Single Lift task", action: "descriptorAutoSwitch", metadata: [
                "reason": reason,
                "from": previous,
                "to": resolution.path
            ])
        } else if resolution.didSwitch && resolution.reason == "quadUsesSingleProp" {
            let previous = modelDescriptorPath.trimmingCharacters(in: .whitespacesAndNewlines)
            modelDescriptorPath = resolution.path
            emitUIAction(level: .warning, message: "Model descriptor auto-switched for quad task", action: "descriptorAutoSwitch", metadata: [
                "reason": reason,
                "from": previous,
                "to": resolution.path
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
        let telemetry: (WorldStepLog) -> Void = { [weak self] step in
            self?.recordLiveStep(step)
        }
        command.setTelemetry(telemetry)
        modelContexts[info.id] = ModelContext(
            store: store,
            commandSystem: command
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
        let telemetry: (WorldStepLog) -> Void = { [weak self] step in
            self?.recordLiveStep(step)
        }
        command.setTelemetry(telemetry)
        modelContexts[selectedModelID] = ModelContext(
            store: store,
            commandSystem: command
        )
        modelStore = store
        commandSystem = command
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
        validationLossSamples.removeAll()
        loopScoreSamples.removeAll()
        rewardAverageSamples.removeAll()
        passRateSamples.removeAll()
        failureRateSamples.removeAll()
        safetyViolationSamples.removeAll()
        workerThroughputSamples.removeAll()
        overshootSamples.removeAll()
        recoverySamples.removeAll()
        hfSamples.removeAll()
        trainingLiveStatus = .idle
        trainingTimeline.removeAll()
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
            if !controllerSelection.isBaselineController {
                emitUIAction(level: .warning, message: "Manual actuators force teacher baseline controller", action: "runBaseline", metadata: [
                    "reason": "manualActuatorEnabled"
                ])
            }
            effectiveController = .teacherBaseline
        } else {
            effectiveController = controllerSelection
        }

        let descendingIntent: ResolvedDescendingIntent
        do {
            descendingIntent = try resolvedDescendingIntent(
                controller: effectiveController,
                action: "runBaseline"
            )
        } catch {
            isRunning = false
            emitError("Invalid descending channels", error: error)
            return
        }

        let overrideParameters: ReferenceQuadrotorParameters?
        do {
            overrideParameters = try preflightParameters(modelPath: resolvedPath)
        } catch {
            isRunning = false
            activeParameters = nil
            emitError("Model preflight failed", error: error)
            return
        }

        let request = SimulationRunRequest(
            controller: effectiveController,
            taskMode: taskMode,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            modelDescriptorPath: resolvedPath,
            overrideParameters: overrideParameters,
            useAux: trainingUseAux,
            useQualityGating: trainingUseQualityGating,
            descendingVector: descendingIntent.vector,
            descendingProgram: descendingIntent.program
        )
        activeParameters = request.overrideParameters

        emitUIAction(
            level: .notice,
            message: "Run started (single)",
            action: "runBaseline",
            metadata: [
                "controller": effectiveController.rawValue,
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
                    let record = self.trainingRunPresenter.buildRunRecord(output: output)
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
                let result = try await commandSystem.submit(
                    .exportDataset(
                        output: run.output,
                        directory: url,
                        observationMetadata: trainingObservationMetadata()
                    )
                )
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

        let request = trainingBootstrapCoordinator.makeRequest(input: TrainingBootstrapInput(
            datasetURL: url,
            sequenceLength: trainingSequenceLength,
            epochs: trainingEpochs,
            learningRate: trainingLearningRate,
            useAux: trainingUseAux,
            useQualityGating: trainingUseQualityGating
        ))

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

        let isPreview = isPreviewEnvironment
        if controllerSelection != .manasMLX {
            emitUIAction(level: .warning, message: "Training loop forces ManasMLX controller", action: "startTrainingLoop", metadata: [
                "from": controllerSelection.rawValue,
                "to": ControllerSelection.manasMLX.rawValue,
                "reason": "loopRequiresManasMLX"
            ])
        }

        let resolvedPath = ensureDescriptorForTask(reason: "startTrainingLoop")
        let descendingIntent: ResolvedDescendingIntent
        do {
            descendingIntent = try resolvedDescendingIntent(
                controller: .manasMLX,
                action: "startTrainingLoop"
            )
        } catch {
            emitError("Invalid descending channels", error: error)
            return
        }
        let overrideParameters: ReferenceQuadrotorParameters?
        do {
            overrideParameters = try preflightParameters(modelPath: resolvedPath)
        } catch {
            activeParameters = nil
            emitError("Model preflight failed", error: error)
            return
        }

        let preparation: TrainingRunPreparation
        do {
            preparation = try trainingRunCoordinator.prepare(input: TrainingRunPreparationInput(
                controllerSelection: controllerSelection,
                taskMode: taskMode,
                kp: kp,
                kd: kd,
                yawDamping: yawDamping,
                hoverThrustScale: hoverThrustScale,
                cutPeriodSteps: cutPeriodSteps,
                determinismSelection: determinismSelection,
                modelDescriptorPath: resolvedPath,
                overrideParameters: overrideParameters,
                descendingIntent: descendingIntent,
                datasetDirectory: trainingDatasetDirectory,
                trainingEpochs: trainingEpochs,
                trainingSequenceLength: trainingSequenceLength,
                trainingLearningRate: trainingLearningRate,
                trainingUseAux: trainingUseAux,
                trainingUseQualityGating: trainingUseQualityGating,
                loopMaxIterations: loopMaxIterations,
                loopEvaluationInterval: loopEvaluationInterval,
                loopStopOnPass: loopStopOnPass,
                loopPatience: loopPatience,
                loopMinDelta: loopMinDelta,
                loopMaxFailures: loopMaxFailures,
                loopAllowAutoBackoff: loopAllowAutoBackoff
            ))
        } catch {
            emitError("Invalid training run config", error: error)
            return
        }

        activeParameters = preparation.runRequest.overrideParameters
        activeLoopController = preparation.controller
        isLoopRunning = true
        isLoopPaused = false
        loopIteration = 0
        loopBestScore = nil
        loopLastScore = nil
        loopStatusMessage = "Loop started"
        loopScoreSamples.removeAll()
        rewardAverageSamples.removeAll()
        passRateSamples.removeAll()
        failureRateSamples.removeAll()
        safetyViolationSamples.removeAll()
        workerThroughputSamples.removeAll()
        overshootSamples.removeAll()
        recoverySamples.removeAll()
        hfSamples.removeAll()
        lastConvergenceSummary = nil
        lastCheckpointDecision = nil
        lastTrainingRunArtifactDirectory = nil
        lastPostRegressionGate = nil
        trainingTimeline.removeAll()
        updateTrainingLiveStatus(
            phase: .preparing,
            message: "Preparing training loop",
            iteration: 0
        )
        emitUIAction(level: .notice, message: "Training loop started", action: "startTrainingLoop", metadata: [
            "controller": preparation.controller.rawValue,
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
            commandSystem.startTrainingLoop(
                config: preparation.loopConfig,
                runRequest: preparation.runRequest,
                trainingTemplate: preparation.trainingTemplate,
                datasetRoot: preparation.datasetRoot
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
            await commandSystem.pauseTrainingLoop()
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
            await commandSystem.resumeTrainingLoop()
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
            await commandSystem.stopTrainingLoop()
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
        applyTrainingLoopState(trainingLoopReducer.reduce(
            state: currentTrainingLoopState(),
            event: event
        ))
        switch event {
        case .started:
            updateTrainingLiveStatus(
                phase: .preparing,
                message: "Training loop started",
                iteration: loopIteration
            )
        case .iterationStarted(let iteration):
            updateTrainingLiveStatus(
                phase: .evaluating,
                message: "Iteration \(iteration)",
                iteration: iteration
            )
            emitTerminal(level: .notice, message: "Loop iteration started", metadata: [
                "iter": "\(iteration)"
            ])
        case .runStarted(let iteration):
            updateTrainingLiveStatus(
                phase: .rollout,
                message: "Policy rollout",
                iteration: iteration
            )
            emitTerminal(level: .notice, message: "Loop run started", metadata: [
                "iter": "\(iteration)"
            ])
        case .teacherRunStarted(let iteration, let hoverThrustScale):
            updateTrainingLiveStatus(
                phase: .rollout,
                message: "Teacher rollout",
                iteration: iteration
            )
            emitTerminal(level: .notice, message: "Teacher run started", metadata: [
                "iter": "\(iteration)",
                "controller": "teacherBaseline",
                "task": taskMode.rawValue,
                "hoverThrustScale": String(format: "%.3f", hoverThrustScale)
            ])
        case .teacherRunCompleted(let iteration, let output):
            updateRunQualityStatus(iteration: iteration, output: output)
            emitTerminal(level: .notice, message: "Teacher run completed", metadata: [
                "iter": "\(iteration)",
                "passed": "\(output.summary.suitePassed)",
                "scenarios": "\(output.logs.count)"
            ])
        case .runCompleted(let iteration, let output, let score):
            let presentation = trainingRunPresenter.runCompleted(
                iteration: iteration,
                output: output,
                score: score
            )
            loopScoreSamples.append(presentation.scoreSample)
            let record = presentation.record
            runs.insert(record, at: 0)
            selectedRunID = record.id
            selectedScenarioKey = record.scenarios.first?.id
            if !output.summary.suitePassed {
                emitScenarioFailures(output: output)
            }
            if let sample = presentation.overshootSample {
                overshootSamples.append(sample)
            }
            if let sample = presentation.recoverySample {
                recoverySamples.append(sample)
            }
            if let sample = presentation.hfSample {
                hfSamples.append(sample)
            }
            updateRunQualityStatus(iteration: iteration, output: output)
            emitTerminal(level: .info, message: "Loop run completed", metadata: presentation.terminalMetadata)
        case .datasetExportStarted(let iteration, let path):
            updateTrainingLiveStatus(
                phase: .datasetExport,
                message: "Exporting dataset",
                iteration: iteration,
                datasetPath: path
            )
            emitTerminal(level: .notice, message: "Dataset export started", metadata: [
                "iter": "\(iteration)",
                "path": path
            ])
        case .datasetExportCompleted(let iteration, let count):
            updateTrainingLiveStatus(
                phase: .datasetExport,
                message: "Dataset exported",
                iteration: iteration,
                datasetCount: count
            )
            emitTerminal(level: .info, message: "Dataset export completed", metadata: [
                "iter": "\(iteration)",
                "count": "\(count)"
            ])
        case .trainingStarted(let iteration, let path, let epochs, let learningRate):
            updateTrainingLiveStatus(
                phase: .supervisedTraining,
                message: "Supervised training",
                iteration: iteration,
                datasetPath: path,
                epochs: epochs,
                learningRate: learningRate
            )
            emitTerminal(level: .notice, message: "Training started", metadata: [
                "iter": "\(iteration)",
                "path": path,
                "epochs": "\(epochs)",
                "lr": String(format: "%.6f", learningRate)
            ])
        case .trainingCompleted(let iteration, let result):
            Self.appendMetricSample(&trainingLossSamples, time: Double(iteration), value: result.finalLoss)
            updateTrainingLiveStatus(
                phase: .evaluating,
                message: "Training completed",
                iteration: iteration,
                epochs: result.epochs
            )
            updateSelectedModel { model in
                model.hasSupervisedBootstrap = true
                model.lastTrainedAt = Date()
            }
            persistSelectedModel()
            emitTerminal(level: .info, message: "Training completed", metadata: [
                "iter": "\(iteration)",
                "loss": String(format: "%.6f", result.finalLoss)
            ])
        case .reinforcementTrainingCompleted(let iteration, let result):
            Self.appendMetricSample(&rewardAverageSamples, time: Double(iteration), value: result.rewardAverage)
            if let finalLoss = result.finalLoss {
                Self.appendMetricSample(&trainingLossSamples, time: Double(iteration), value: finalLoss)
            }
            updateTrainingLiveStatus(
                phase: .reinforcementTraining,
                message: "Reinforcement training completed",
                iteration: iteration
            )
            updateSelectedModel { model in
                model.lastTrainedAt = Date()
            }
            persistSelectedModel()
            var metadata: [String: String] = [
                "iter": "\(iteration)",
                "rewardAverage": String(format: "%.6f", result.rewardAverage)
            ]
            if let finalLoss = result.finalLoss {
                metadata["loss"] = String(format: "%.6f", finalLoss)
            }
            if let checkpointID = result.candidateCheckpointID {
                metadata["candidateCheckpoint"] = checkpointID
            }
            emitTerminal(level: .info, message: "Reinforcement training completed", metadata: metadata)
        case .backoffApplied(let newLearningRate):
            updateTrainingLiveStatus(
                phase: trainingLiveStatus.phase,
                message: "Learning rate backoff",
                iteration: loopIteration,
                learningRate: newLearningRate
            )
            emitTerminal(level: .notice, message: "Learning rate backoff", metadata: [
                "lr": String(format: "%.6f", newLearningRate)
            ])
        case .paused:
            updateTrainingLiveStatus(
                phase: .paused,
                message: "Paused",
                iteration: loopIteration
            )
        case .resumed:
            updateTrainingLiveStatus(
                phase: .evaluating,
                message: "Running",
                iteration: loopIteration
            )
        case .stopped:
            updateTrainingLiveStatus(
                phase: .stopped,
                message: "Stopped",
                iteration: loopIteration
            )
        case .completed(let summary):
            applyTrainingRunArtifacts(from: summary.artifactDirectory)
            updateTrainingLiveStatus(
                phase: .completed,
                message: summary.passed ? "Completed (accepted)" : "Completed (rejected)",
                iteration: summary.iterations,
                artifactDirectoryPath: summary.artifactDirectory.path,
                convergence: summary.convergence,
                checkpointDecision: summary.checkpointDecision
            )
            emitTerminal(level: .info, message: "Training loop completed", metadata: [
                "iterations": "\(summary.iterations)",
                "bestScore": String(format: "%.3f", summary.bestScore),
                "checkpointDecision": summary.checkpointDecision.state.rawValue,
                "artifactDirectory": summary.artifactDirectory.path
            ])
        case .failed(let message):
            updateTrainingLiveStatus(
                phase: .failed,
                message: message,
                iteration: loopIteration
            )
            emitTerminal(level: .error, message: message)
        }
    }

    private func currentTrainingLoopState() -> TrainingLoopStateSnapshot {
        TrainingLoopStateSnapshot(
            isLoopRunning: isLoopRunning,
            isLoopPaused: isLoopPaused,
            loopIteration: loopIteration,
            loopBestScore: loopBestScore,
            loopLastScore: loopLastScore,
            loopStatusMessage: loopStatusMessage,
            activeLoopController: activeLoopController,
            trainingLearningRate: trainingLearningRate,
            lastTrainingLoss: lastTrainingLoss,
            lastTrainingRunArtifactDirectory: lastTrainingRunArtifactDirectory,
            lastConvergenceSummary: lastConvergenceSummary,
            lastCheckpointDecision: lastCheckpointDecision
        )
    }

    private func applyTrainingLoopState(_ state: TrainingLoopStateSnapshot) {
        isLoopRunning = state.isLoopRunning
        isLoopPaused = state.isLoopPaused
        loopIteration = state.loopIteration
        loopBestScore = state.loopBestScore
        loopLastScore = state.loopLastScore
        loopStatusMessage = state.loopStatusMessage
        activeLoopController = state.activeLoopController
        trainingLearningRate = state.trainingLearningRate
        lastTrainingLoss = state.lastTrainingLoss
        lastTrainingRunArtifactDirectory = state.lastTrainingRunArtifactDirectory
        lastConvergenceSummary = state.lastConvergenceSummary
        lastCheckpointDecision = state.lastCheckpointDecision
    }

    private func applyTrainingRunArtifacts(from directory: URL) {
        do {
            let state = try trainingRunStore.load(from: directory)
            trainingLossSamples = state.lossSamples
            validationLossSamples = state.validationLossSamples
            loopScoreSamples = state.scoreSamples
            rewardAverageSamples = state.rewardAverageSamples
            passRateSamples = state.passRateSamples
            failureRateSamples = state.failureRateSamples
            safetyViolationSamples = state.safetyViolationSamples
            workerThroughputSamples = state.workerThroughputSamples
            lastConvergenceSummary = state.convergence
            lastCheckpointDecision = state.checkpointDecision
            applyPostRegressionArtifactsIfPresent(near: directory)
            updateTrainingLiveStatus(
                phase: trainingLiveStatus.phase,
                message: trainingLiveStatus.message,
                iteration: loopIteration,
                artifactDirectoryPath: state.artifactDirectory.path,
                convergence: state.convergence,
                checkpointDecision: state.checkpointDecision
            )
        } catch {
            emitTerminal(level: .warning, message: "Training artifacts unavailable", metadata: [
                "path": directory.path,
                "error": "\(error)"
            ])
        }
    }

    func loadPostRegressionGate(from artifactDirectory: URL) {
        do {
            lastPostRegressionGate = try regressionRunStore.load(from: artifactDirectory)
        } catch {
            emitTerminal(level: .warning, message: "Post-regression artifacts unavailable", metadata: [
                "path": artifactDirectory.path,
                "error": "\(error)"
            ])
        }
    }

    func useCurrentLearningCampaignArtifactRoot() {
        let pointer = URL(fileURLWithPath: "/tmp/kuyu-current-campaign-root.txt")
        do {
            let value = try String(contentsOf: pointer, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                learningCampaignError = "Current campaign pointer is empty."
                emitUIAction(level: .warning, message: "Current learning campaign pointer is empty", action: "useCurrentLearningCampaign")
                return
            }
            learningCampaignArtifactDirectory = value
            loadLearningCampaignArtifacts()
        } catch {
            learningCampaignError = "\(error)"
            emitUIAction(level: .warning, message: "Current learning campaign pointer unavailable", action: "useCurrentLearningCampaign", metadata: [
                "path": pointer.path,
                "error": "\(error)"
            ])
        }
    }

    func useCurrentBestLearningCheckpoint() {
        let pointer = URL(fileURLWithPath: "/tmp/kuyu-current-best-checkpoint.txt")
        do {
            let value = try String(contentsOf: pointer, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                learningCampaignError = "Current best checkpoint pointer is empty."
                emitUIAction(level: .warning, message: "Current best checkpoint pointer is empty", action: "useCurrentBestLearningCheckpoint")
                return
            }
            learningCampaignSourceCheckpointPath = value
            emitUIAction(level: .info, message: "Learning campaign source checkpoint selected", action: "useCurrentBestLearningCheckpoint", metadata: [
                "path": value
            ])
        } catch {
            learningCampaignError = "\(error)"
            emitUIAction(level: .warning, message: "Current best checkpoint pointer unavailable", action: "useCurrentBestLearningCheckpoint", metadata: [
                "path": pointer.path,
                "error": "\(error)"
            ])
        }
    }

    func prepareNewLearningCampaignArtifactRoot() {
        let task = learningCampaignTaskName()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        learningCampaignArtifactDirectory = "/tmp/kuyu-ui-\(task)-campaign-\(stamp)"
        emitUIAction(level: .info, message: "Learning campaign artifact root prepared", action: "prepareLearningCampaignArtifactRoot", metadata: [
            "path": learningCampaignArtifactDirectory
        ])
    }

    func selectLearningStrategy(_ strategy: LearningStrategySelection) {
        guard strategy.isExecutable else {
            let reason = strategy.unavailableReason ?? "\(strategy.title) is not executable in the learning campaign runner."
            learningCampaignReadiness = .blocked(message: reason)
            learningCampaignError = reason
            emitUIAction(level: .warning, message: "Learning strategy is not executable", action: "selectLearningStrategy", metadata: [
                "strategy": strategy.rawValue,
                "reason": reason
            ])
            return
        }

        learningStrategySelection = strategy
        learningCampaignReadiness = .idle
        learningCampaignError = nil
        emitUIAction(level: .info, message: "Learning strategy selected", action: "selectLearningStrategy", metadata: [
            "strategy": strategy.rawValue
        ])
    }

    func validateLearningCampaignLaunch() {
        do {
            let config = try makeLearningCampaignRunConfig(prepareMissingInputs: true)
            try commandSystem.validateLearningCampaign(config: config)
            learningCampaignLaunchEstimate = makeLearningCampaignLaunchEstimate(suites: config.suites)
            learningCampaignReadiness = .ready(message: "Source checkpoint, descriptor, suites, and artifact root are valid.")
            learningCampaignError = nil
            emitUIAction(level: .notice, message: "Learning campaign dry validation passed", action: "validateLearningCampaign", metadata: [
                "task": config.task.rawValue,
                "artifactRoot": config.artifactRoot.path,
                "sourceCheckpoint": config.sourceCheckpoint.path
            ])
        } catch {
            learningCampaignReadiness = .blocked(message: "\(error)")
            learningCampaignError = "\(error)"
            emitUIAction(level: .warning, message: "Learning campaign dry validation failed", action: "validateLearningCampaign", metadata: [
                "error": "\(error)"
            ])
        }
    }

    func estimateLearningCampaignCost() {
        do {
            let suites = try learningCampaignSuiteValues()
            learningCampaignLaunchEstimate = makeLearningCampaignLaunchEstimate(suites: suites)
            learningCampaignError = nil
            emitUIAction(level: .info, message: "Learning campaign estimate refreshed", action: "estimateLearningCampaignCost", metadata: [
                "candidateEvaluations": "\(learningCampaignLaunchEstimate?.candidateEvaluations ?? 0)",
                "regressionEpisodes": "\(learningCampaignLaunchEstimate?.regressionEpisodes ?? 0)"
            ])
        } catch {
            learningCampaignError = "\(error)"
            learningCampaignReadiness = .blocked(message: "\(error)")
            emitUIAction(level: .warning, message: "Learning campaign estimate failed", action: "estimateLearningCampaignCost", metadata: [
                "error": "\(error)"
            ])
        }
    }

    func saveLearningCampaignTemplate() {
        do {
            if learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prepareNewLearningCampaignArtifactRoot()
            }
            let root = URL(fileURLWithPath: learningCampaignArtifactDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let draft = LearningCampaignTemplateDraft(
                name: learningCampaignExperimentName,
                description: learningCampaignExperimentDescription,
                tags: learningCampaignTagValues(),
                task: learningCampaignTask().rawValue,
                suites: learningCampaignSuites,
                seedCount: learningCampaignSeedCount,
                population: learningCampaignPopulation,
                generations: learningCampaignGenerations,
                episodes: learningCampaignEpisodes,
                strategy: learningStrategySelection.rawValue,
                preset: learningCampaignPreset.rawValue,
                artifactRetention: learningCampaignCompactRetention ? "compact" : "full",
                createdAt: Date()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(draft)
            let url = root.appendingPathComponent("training-template-draft.json")
            try data.write(to: url, options: .atomic)
            learningCampaignTemplateStatus = "Saved \(url.lastPathComponent)"
            learningCampaignError = nil
            emitUIAction(level: .notice, message: "Learning campaign template saved", action: "saveLearningCampaignTemplate", metadata: [
                "path": url.path,
                "strategy": draft.strategy
            ])
        } catch {
            learningCampaignTemplateStatus = nil
            learningCampaignError = "\(error)"
            emitUIAction(level: .warning, message: "Learning campaign template save failed", action: "saveLearningCampaignTemplate", metadata: [
                "error": "\(error)"
            ])
        }
    }

    func queueLearningCampaignRun() {
        do {
            let suites = try learningCampaignSuiteValues()
            let estimate = makeLearningCampaignLaunchEstimate(suites: suites)
            learningCampaignLaunchEstimate = estimate
            let queuedRun = LearningCampaignQueuedRun(
                id: UUID(),
                name: learningCampaignExperimentName,
                strategy: learningStrategySelection,
                candidateEvaluations: estimate.candidateEvaluations,
                regressionEpisodes: estimate.regressionEpisodes,
                queuedAt: Date()
            )
            learningCampaignQueuedRuns.append(queuedRun)
            learningCampaignError = nil
            emitUIAction(level: .notice, message: "Learning campaign queued", action: "queueLearningCampaignRun", metadata: [
                "name": queuedRun.name,
                "candidateEvaluations": "\(queuedRun.candidateEvaluations)",
                "regressionEpisodes": "\(queuedRun.regressionEpisodes)"
            ])
        } catch {
            learningCampaignError = "\(error)"
            emitUIAction(level: .warning, message: "Learning campaign queue failed", action: "queueLearningCampaignRun", metadata: [
                "error": "\(error)"
            ])
        }
    }

    func startLearningCampaign() {
        if isLearningCampaignRunning || learningCampaignHandle != nil {
            emitUIAction(level: .warning, message: "Learning campaign already running", action: "startLearningCampaign")
            return
        }

        do {
            let config = try makeLearningCampaignRunConfig(prepareMissingInputs: true)
            let handle = try commandSystem.startLearningCampaign(config: config)
            learningCampaignHandle = handle
            isLearningCampaignRunning = true
            learningCampaignError = nil
            learningCampaignLaunchEstimate = makeLearningCampaignLaunchEstimate(suites: config.suites)
            learningCampaignReadiness = .ready(message: "Campaign launched with validated config.")
            learningCampaignProgressFraction = handle.progress.fractionCompleted
            learningCampaignCurrentPhase = "starting"
            learningCampaignLatestEvent = nil
            startLearningCampaignEventMonitoring(handle: handle)
            startLearningCampaignWaitTask(handle: handle)
            startLearningCampaignMonitoring()
            emitUIAction(level: .notice, message: "Learning campaign started", action: "startLearningCampaign", metadata: [
                "task": config.task.rawValue,
                "artifactRoot": config.artifactRoot.path,
                "sourceCheckpoint": config.sourceCheckpoint.path,
                "seedCount": "\(config.seedCount)",
                "population": "\(config.population)",
                "generations": "\(config.generations)"
            ])
        } catch {
            isLearningCampaignRunning = false
            learningCampaignError = "\(error)"
            learningCampaignReadiness = .blocked(message: "\(error)")
            emitUIAction(level: .error, message: "Learning campaign launch failed", action: "startLearningCampaign", metadata: [
                "error": "\(error)"
            ])
        }
    }

    func stopLearningCampaign() {
        learningCampaignHandle?.cancel()
        isLearningCampaignRunning = false
        learningCampaignCurrentPhase = "cancelling"
        emitUIAction(level: .notice, message: "Learning campaign stop requested", action: "stopLearningCampaign")
    }

    func stepSimulationPlayback() {
        simulationPlaybackFraction = min(1, simulationPlaybackFraction + 0.02)
        emitUIAction(level: .info, message: "Simulation playback stepped", action: "stepSimulationPlayback", metadata: [
            "fraction": String(format: "%.2f", simulationPlaybackFraction)
        ])
    }

    func resetSimulationPlayback() {
        simulationPlaybackFraction = 0
        emitUIAction(level: .info, message: "Simulation playback reset", action: "resetSimulationPlayback")
    }

    func exportLearningReport(format: ReportExportFormat) {
        do {
            let root = reportExportRoot()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("bounded-learning-report.\(format.fileExtension)")
            let data = try reportData(format: format)
            try data.write(to: url, options: .atomic)
            reportExportStatus = "Exported \(url.lastPathComponent)"
            emitUIAction(level: .notice, message: "Learning report exported", action: "exportLearningReport", metadata: [
                "format": format.rawValue,
                "path": url.path
            ])
        } catch {
            reportExportStatus = "\(error)"
            emitUIAction(level: .warning, message: "Learning report export failed", action: "exportLearningReport", metadata: [
                "format": format.rawValue,
                "error": "\(error)"
            ])
        }
    }

    func loadLearningCampaignArtifacts() {
        let path = learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            learningCampaignError = "Artifact directory is empty."
            return
        }

        let directory = URL(fileURLWithPath: path, isDirectory: true)
        do {
            learningCampaignState = try learningCampaignRunStore.load(from: directory)
            learningCampaignError = nil
            isLearningCampaignRunning = learningCampaignHandle != nil || (learningCampaignState?.isActive == true)
        } catch {
            learningCampaignError = "\(error)"
            isLearningCampaignRunning = learningCampaignHandle != nil
            emitTerminal(level: .warning, message: "Learning campaign artifacts unavailable", metadata: [
                "path": directory.path,
                "error": "\(error)"
            ])
        }
    }

    func startLearningCampaignMonitoring() {
        let path = learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            useCurrentLearningCampaignArtifactRoot()
            guard !learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            startLearningCampaignMonitoring()
            return
        }

        learningCampaignMonitorTask?.cancel()
        learningCampaignMonitorEnabled = true
        emitUIAction(level: .notice, message: "Learning campaign monitor started", action: "startLearningCampaignMonitor", metadata: [
            "path": path
        ])

        learningCampaignMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.loadLearningCampaignArtifacts()
                }
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
            }
        }
    }

    func stopLearningCampaignMonitoring() {
        learningCampaignMonitorTask?.cancel()
        learningCampaignMonitorTask = nil
        learningCampaignMonitorEnabled = false
        emitUIAction(level: .notice, message: "Learning campaign monitor stopped", action: "stopLearningCampaignMonitor")
    }

    private func startLearningCampaignEventMonitoring(handle: LearningCampaignRunHandle) {
        learningCampaignEventTask?.cancel()
        learningCampaignEventTask = Task { [weak self] in
            for await event in handle.events {
                await MainActor.run {
                    self?.applyLearningCampaignEvent(event, progress: handle.progress)
                }
            }
        }
    }

    private func startLearningCampaignWaitTask(handle: LearningCampaignRunHandle) {
        learningCampaignWaitTask?.cancel()
        learningCampaignWaitTask = Task { [weak self] in
            do {
                _ = try await handle.wait()
                await MainActor.run {
                    self?.learningCampaignHandle = nil
                    self?.learningCampaignEventTask = nil
                    self?.learningCampaignWaitTask = nil
                    self?.isLearningCampaignRunning = false
                    self?.learningCampaignProgressFraction = 1
                    self?.loadLearningCampaignArtifacts()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.learningCampaignHandle = nil
                    self?.learningCampaignEventTask = nil
                    self?.learningCampaignWaitTask = nil
                    self?.isLearningCampaignRunning = false
                    self?.learningCampaignCurrentPhase = "cancelled"
                    self?.loadLearningCampaignArtifacts()
                }
            } catch {
                await MainActor.run {
                    self?.learningCampaignHandle = nil
                    self?.learningCampaignEventTask = nil
                    self?.learningCampaignWaitTask = nil
                    self?.isLearningCampaignRunning = false
                    self?.learningCampaignError = "\(error)"
                    self?.learningCampaignCurrentPhase = "failed"
                    self?.loadLearningCampaignArtifacts()
                }
            }
        }
    }

    private func applyLearningCampaignEvent(
        _ event: LearningCampaignRunEvent,
        progress: Progress
    ) {
        learningCampaignProgressFraction = progress.fractionCompleted
        switch event {
        case .preflightStarted:
            learningCampaignCurrentPhase = "preflight"
            learningCampaignLatestEvent = "Preflight started"
        case .preflightCompleted:
            learningCampaignCurrentPhase = "preflight"
            learningCampaignLatestEvent = "Preflight completed"
        case .parentEvaluationStarted(let label, _):
            learningCampaignCurrentPhase = "checkpoint evaluation"
            learningCampaignLatestEvent = "\(label) evaluation started"
        case .parentEvaluationCompleted(let label, _):
            learningCampaignCurrentPhase = "checkpoint evaluation"
            learningCampaignLatestEvent = "\(label) evaluation completed"
        case .checkpointRegressionStarted(let label, _):
            learningCampaignCurrentPhase = "regression"
            learningCampaignLatestEvent = "\(label) regression started"
        case .checkpointRegressionCompleted(let label, let accepted, let reasons):
            learningCampaignCurrentPhase = "regression"
            learningCampaignLatestEvent = "\(label) regression \(accepted ? "accepted" : reasons.joined(separator: ","))"
        case .seedStarted(let seed):
            learningCampaignCurrentPhase = "seed \(seed)"
            learningCampaignLatestEvent = "Seed \(seed) started"
        case .generationStarted(let seed, let generationIndex):
            learningCampaignCurrentPhase = "seed \(seed) generation \(generationIndex)"
            learningCampaignLatestEvent = "Generation \(generationIndex) started"
        case .candidateEvaluated(_, let generationIndex, let candidateID, let fitness):
            learningCampaignCurrentPhase = "generation \(generationIndex)"
            learningCampaignLatestEvent = "\(candidateID) fitness \(String(format: "%.3f", fitness))"
        case .generationCompleted(let seed, let generationIndex, let bestCandidateID):
            learningCampaignCurrentPhase = "seed \(seed)"
            learningCampaignLatestEvent = "Generation \(generationIndex) best \(bestCandidateID ?? "none")"
        case .seedCompleted(let seed, let accepted, let bestCandidateID):
            learningCampaignCurrentPhase = "seed \(seed)"
            learningCampaignLatestEvent = "Seed \(seed) \(accepted ? "accepted" : "rejected") best \(bestCandidateID ?? "none")"
        case .artifactWritten(let name, _):
            learningCampaignLatestEvent = "Artifact \(name)"
        case .finished:
            learningCampaignCurrentPhase = "finished"
            learningCampaignLatestEvent = "Campaign finished"
        case .failed(let reason):
            learningCampaignCurrentPhase = "failed"
            learningCampaignLatestEvent = reason
        case .cancelled:
            learningCampaignCurrentPhase = "cancelled"
            learningCampaignLatestEvent = "Campaign cancelled"
        }
        if shouldReloadLearningCampaignArtifacts(for: event) {
            loadLearningCampaignArtifacts()
        }
    }

    private func shouldReloadLearningCampaignArtifacts(for event: LearningCampaignRunEvent) -> Bool {
        switch event {
        case .artifactWritten, .seedCompleted, .finished, .failed, .cancelled:
            return true
        case .preflightStarted,
             .preflightCompleted,
             .parentEvaluationStarted,
             .parentEvaluationCompleted,
             .checkpointRegressionStarted,
             .checkpointRegressionCompleted,
             .seedStarted,
             .generationStarted,
             .candidateEvaluated,
             .generationCompleted:
            return false
        }
    }

    private func learningCampaignTaskName() -> String {
        switch taskMode {
        case .attitude, .lift:
            return "lift"
        case .singleLift:
            return "singleLift"
        }
    }

    private func learningCampaignTask() -> LearningCampaignTask {
        switch taskMode {
        case .attitude, .lift:
            return .lift
        case .singleLift:
            return .singleLift
        }
    }

    private func applyLearningCampaignPreset(_ preset: LearningCampaignRunPreset) {
        let sourcePath = learningCampaignSourceCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let artifactPath = learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = LearningCampaignRunConfig(
            task: learningCampaignTask(),
            sourceCheckpoint: URL(fileURLWithPath: sourcePath.isEmpty ? "/tmp/kuyu-missing-source" : sourcePath, isDirectory: true),
            artifactRoot: URL(fileURLWithPath: artifactPath.isEmpty ? "/tmp/kuyu-missing-artifact-root" : artifactPath, isDirectory: true)
        )
        let config = preset.apply(to: base)
        learningCampaignSuites = config.suites.map(String.init).joined(separator: ",")
        learningCampaignSeedCount = config.seedCount
        learningCampaignPopulation = config.population
        learningCampaignGenerations = config.generations
        learningCampaignEliteCount = config.eliteCount
        learningCampaignWorkers = config.workers
        learningCampaignCandidateEvaluationConcurrency = config.candidateEvaluationConcurrency
        learningCampaignEpisodes = config.episodes
        learningCampaignAdaptiveMutation = config.adaptiveMutationEnabled
        learningCampaignMinimumIncumbentImprovement = config.minimumIncumbentImprovement
        learningCampaignCompactRetention = config.artifactRetention == .compact
        learningCampaignReadiness = .idle
        emitUIAction(level: .info, message: "Learning campaign preset applied", action: "setLearningCampaignPreset", metadata: [
            "preset": preset.rawValue
        ])
    }

    private func makeLearningCampaignRunConfig(prepareMissingInputs: Bool) throws -> LearningCampaignRunConfig {
        guard learningStrategySelection.isExecutable else {
            throw LearningCampaignRunError.invalidConfig(
                "\(learningStrategySelection.title) is not executable. Select Hybrid to use the shared learning campaign runner."
            )
        }

        if prepareMissingInputs && learningCampaignSourceCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            useCurrentBestLearningCheckpoint()
        }
        if prepareMissingInputs && learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prepareNewLearningCampaignArtifactRoot()
        }

        let sourcePath = learningCampaignSourceCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let artifactPath = learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourcePath.isEmpty, !artifactPath.isEmpty else {
            throw LearningCampaignRunError.invalidConfig("Source checkpoint and artifact directory are required.")
        }

        return LearningCampaignRunConfig(
            task: learningCampaignTask(),
            sourceCheckpoint: URL(fileURLWithPath: sourcePath, isDirectory: true),
            artifactRoot: URL(fileURLWithPath: artifactPath, isDirectory: true),
            explicitSeeds: nil,
            seedCount: learningCampaignSeedCount,
            population: learningCampaignPopulation,
            generations: learningCampaignGenerations,
            eliteCount: learningCampaignEliteCount,
            workers: learningCampaignWorkers,
            candidateEvaluationConcurrency: learningCampaignCandidateEvaluationConcurrency,
            suites: try learningCampaignSuiteValues(),
            episodes: learningCampaignEpisodes,
            tier: learningCampaignTier(),
            cutPeriodSteps: cutPeriodSteps,
            modelDescriptorPath: ensureDescriptorForTask(reason: "learningCampaignConfig"),
            mutationRate: learningCampaignMutationRate,
            mutationNoiseScale: learningCampaignMutationNoiseScale,
            adaptiveMutationEnabled: learningCampaignAdaptiveMutation,
            searchStrategy: .qualityDiversity,
            variation: .gaussian,
            minimumIncumbentImprovement: learningCampaignMinimumIncumbentImprovement,
            artifactRetention: learningCampaignCompactRetention ? .compact : .full,
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverScale: hoverThrustScale
        )
    }

    private func makeLearningCampaignLaunchEstimate(suites: [Int]) -> LearningCampaignLaunchEstimate {
        let candidateEvaluations = max(1, learningCampaignSeedCount)
            * max(1, learningCampaignPopulation)
            * max(1, learningCampaignGenerations)
        let regressionRollouts = candidateEvaluations * max(1, suites.count)
        let regressionEpisodes = regressionRollouts * max(1, learningCampaignEpisodes)
        return LearningCampaignLaunchEstimate(
            candidateEvaluations: candidateEvaluations,
            regressionRollouts: regressionRollouts,
            regressionEpisodes: regressionEpisodes,
            workerCount: learningCampaignWorkers,
            candidateConcurrency: learningCampaignCandidateEvaluationConcurrency,
            retention: learningCampaignCompactRetention ? "compact" : "full",
            estimatedAt: Date()
        )
    }

    private func learningCampaignTagValues() -> [String] {
        learningCampaignTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func learningCampaignTier() -> LearningCampaignTier {
        switch determinismSelection {
        case .tier0:
            return .tier0
        case .tier1:
            return .tier1
        case .tier2:
            return .tier2
        }
    }

    private func learningCampaignSuiteValues() throws -> [Int] {
        let tokens = learningCampaignSuites
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [6] }
        return try tokens.map { token in
            guard let suite = Int(token) else {
                throw LearningCampaignRunError.invalidConfig("Invalid suite: \(token)")
            }
            return suite
        }
    }

    private func reportExportRoot() -> URL {
        let artifactPath = learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !artifactPath.isEmpty {
            return URL(fileURLWithPath: artifactPath, isDirectory: true)
                .appendingPathComponent("reports", isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bounded-reports", isDirectory: true)
    }

    private func reportData(format: ReportExportFormat) throws -> Data {
        switch format {
        case .markdown:
            return Data(reportMarkdown().utf8)
        case .html:
            return Data(reportHTML().utf8)
        case .json:
            let payload = ReportExportPayload(
                generatedAt: Date(),
                project: "Bounded",
                task: taskMode.rawValue,
                campaignStatus: learningCampaignState?.statusLabel,
                readiness: learningCampaignReadiness.status.label,
                acceptedCount: learningCampaignState?.acceptedCount,
                seedCount: learningCampaignState?.seedCount,
                bestDelta: learningCampaignState?.bestDelta,
                finalCheckpoint: learningCampaignState?.finalCheckpoint,
                rewardSampleCount: rewardAverageSamples.count,
                runCount: runs.count,
                logCount: logStore.entries.count
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(payload)
        case .csv:
            return Data(reportCSV().utf8)
        }
    }

    private func reportMarkdown() -> String {
        """
        # Bounded Learning Report

        - Task: \(taskMode.rawValue)
        - Campaign Status: \(learningCampaignState?.statusLabel ?? "--")
        - Readiness: \(learningCampaignReadiness.status.label)
        - Accepted: \(learningCampaignState.map { "\($0.acceptedCount)/\($0.seedCount)" } ?? "--")
        - Best Delta: \(learningCampaignState?.bestDelta.map { String(format: "%.3f", $0) } ?? "--")
        - Final Checkpoint: \(learningCampaignState?.finalCheckpoint ?? "--")
        - Runs: \(runs.count)
        - Reward Samples: \(rewardAverageSamples.count)
        - Logs: \(logStore.entries.count)

        ## Latest Event

        \(learningCampaignLatestEvent ?? "No event")
        """
    }

    private func reportHTML() -> String {
        """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"><title>Bounded Learning Report</title></head>
        <body>
        <h1>Bounded Learning Report</h1>
        <ul>
        <li>Task: \(taskMode.rawValue)</li>
        <li>Campaign Status: \(learningCampaignState?.statusLabel ?? "--")</li>
        <li>Readiness: \(learningCampaignReadiness.status.label)</li>
        <li>Accepted: \(learningCampaignState.map { "\($0.acceptedCount)/\($0.seedCount)" } ?? "--")</li>
        <li>Best Delta: \(learningCampaignState?.bestDelta.map { String(format: "%.3f", $0) } ?? "--")</li>
        <li>Final Checkpoint: \(learningCampaignState?.finalCheckpoint ?? "--")</li>
        </ul>
        </body>
        </html>
        """
    }

    private func reportCSV() -> String {
        let acceptedCount = learningCampaignState.map { String($0.acceptedCount) } ?? ""
        let seedCount = learningCampaignState.map { String($0.seedCount) } ?? ""
        let bestDelta = learningCampaignState?.bestDelta.map { String($0) } ?? ""
        let rows: [(String, String)] = [
            ("task", taskMode.rawValue),
            ("campaignStatus", learningCampaignState?.statusLabel ?? ""),
            ("readiness", learningCampaignReadiness.status.label),
            ("acceptedCount", acceptedCount),
            ("seedCount", seedCount),
            ("bestDelta", bestDelta),
            ("finalCheckpoint", learningCampaignState?.finalCheckpoint ?? ""),
            ("runCount", "\(runs.count)"),
            ("rewardSampleCount", "\(rewardAverageSamples.count)"),
            ("logCount", "\(logStore.entries.count)")
        ]
        return "metric,value\n" + rows.map { "\($0.0),\(escapeCSV($0.1))" }.joined(separator: "\n") + "\n"
    }

    private func escapeCSV(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private func applyPostRegressionArtifactsIfPresent(near artifactDirectory: URL) {
        let candidates = [
            artifactDirectory.appendingPathComponent("post-regression", isDirectory: true),
            artifactDirectory
        ]
        for candidate in candidates {
            let summary = candidate.appendingPathComponent("kuyu-regression-summary.json")
            if FileManager.default.fileExists(atPath: summary.path) {
                loadPostRegressionGate(from: candidate)
                return
            }
        }
    }

    private func updateRunQualityStatus(iteration: Int, output: KuyAtt1RunOutput) {
        let evaluations = output.summary.evaluations
        let total = max(evaluations.count, 1)
        let passCount = evaluations.filter(\.passed).count
        let passRate = Double(passCount) / Double(total)
        let failureRate = Double(total - passCount) / Double(total)
        let safetyViolationSeconds = evaluations.reduce(0.0) { partial, evaluation in
            partial + evaluation.sustainedViolationSeconds
        }
        Self.appendMetricSample(&passRateSamples, time: Double(iteration), value: passRate)
        Self.appendMetricSample(&failureRateSamples, time: Double(iteration), value: failureRate)
        Self.appendMetricSample(&safetyViolationSamples, time: Double(iteration), value: safetyViolationSeconds)
        updateTrainingLiveStatus(
            phase: .evaluating,
            message: output.summary.suitePassed ? "Suite passed" : "Suite failed",
            iteration: iteration,
            passRate: passRate,
            failureRate: failureRate,
            safetyViolationSeconds: safetyViolationSeconds,
            lastRunPassed: output.summary.suitePassed
        )
    }

    private func updateTrainingLiveStatus(
        phase: TrainingLiveStatus.Phase,
        message: String,
        iteration: Int,
        datasetPath: String? = nil,
        datasetCount: Int? = nil,
        epochs: Int? = nil,
        learningRate: Double? = nil,
        passRate: Double? = nil,
        failureRate: Double? = nil,
        safetyViolationSeconds: Double? = nil,
        lastRunPassed: Bool? = nil,
        artifactDirectoryPath: String? = nil,
        convergence: ConvergenceSummary? = nil,
        checkpointDecision: CheckpointDecision? = nil
    ) {
        trainingLiveStatus.phase = phase
        trainingLiveStatus.message = message
        trainingLiveStatus.iteration = iteration
        trainingLiveStatus.datasetPath = datasetPath ?? trainingLiveStatus.datasetPath
        trainingLiveStatus.datasetCount = datasetCount ?? trainingLiveStatus.datasetCount
        trainingLiveStatus.epochs = epochs ?? trainingLiveStatus.epochs
        trainingLiveStatus.learningRate = learningRate ?? trainingLiveStatus.learningRate
        trainingLiveStatus.passRate = passRate ?? trainingLiveStatus.passRate
        trainingLiveStatus.failureRate = failureRate ?? trainingLiveStatus.failureRate
        trainingLiveStatus.safetyViolationSeconds = safetyViolationSeconds ?? trainingLiveStatus.safetyViolationSeconds
        trainingLiveStatus.lastRunPassed = lastRunPassed ?? trainingLiveStatus.lastRunPassed
        trainingLiveStatus.artifactDirectoryPath = artifactDirectoryPath ?? trainingLiveStatus.artifactDirectoryPath
        if let convergence {
            trainingLiveStatus.convergenceAccepted = convergence.accepted
            trainingLiveStatus.convergenceReason = convergence.reason
            trainingLiveStatus.plateauDetected = convergence.plateauDetected
            trainingLiveStatus.overfitRiskDetected = convergence.overfitRiskDetected
            trainingLiveStatus.safetyRegressionDetected = convergence.safetyRegressionDetected
            trainingLiveStatus.bestCheckpointID = convergence.bestCheckpointID
        }
        if let checkpointDecision {
            trainingLiveStatus.checkpointState = checkpointDecision.state.rawValue
            trainingLiveStatus.checkpointReason = checkpointDecision.reason
        }
        trainingLiveStatus.updatedAt = Date()
        appendTrainingTimeline(phase: phase, message: message, iteration: iteration)
    }

    private func appendTrainingTimeline(
        phase: TrainingLiveStatus.Phase,
        message: String,
        iteration: Int
    ) {
        if trainingTimeline.last?.phase == phase,
           trainingTimeline.last?.message == message,
           trainingTimeline.last?.iteration == iteration {
            return
        }
        trainingTimeline.insert(TrainingTimelineEntry(phase: phase, message: message, iteration: iteration), at: 0)
        if trainingTimeline.count > 16 {
            trainingTimeline.removeLast(trainingTimeline.count - 16)
        }
    }

    private static func appendMetricSample(
        _ samples: inout [MetricSample],
        time: Double,
        value: Double
    ) {
        guard value.isFinite else { return }
        samples.append(MetricSample(time: time, value: value))
        if samples.count > 512 {
            samples.removeFirst(samples.count - 512)
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

    func setModelDescriptorPath(_ path: String, source: String, emitLog: Bool = true) {
        modelDescriptorPath = path
        descriptorCachePath = nil
        descriptorCache = nil
        descriptorCacheError = nil
        refreshManualActuatorLayout()
        guard emitLog else { return }
        emitUIAction(level: .info, message: "Model descriptor set", action: "setDescriptorPath", metadata: [
            "source": source,
            "path": path
        ])
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
            emitUIAction(level: .info, message: "Model descriptor path resolved", action: "descriptorPathResolved", metadata: [
                "from": previous,
                "to": resolved,
                "reason": "defaultPath"
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

    private func trainingObservationMetadata() -> TrainingObservationMetadata? {
        guard let observation = descriptorSnapshot()?.descriptor.observation else { return nil }
        return TrainingObservationMetadata(observation: observation)
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

    private func preflightParameters(modelPath: String) throws -> ReferenceQuadrotorParameters? {
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
            emitUIAction(level: .error, message: "Model load failed", action: "modelPreflight", metadata: [
                "path": trimmed,
                "reason": "loadFailed",
                "error": "\(error)"
            ])
            throw error
        }
    }

    private func preflightParameters() throws -> ReferenceQuadrotorParameters? {
        try preflightParameters(modelPath: resolvedDescriptorPath())
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
                commandSystem: commandSystem
            )
            return
        }

        availableModels = persisted
        modelContexts.removeAll()
        for model in persisted {
            let store = ManasMLXModelStore()
            let command = CommandSystem(modelStore: store)
            command.setManualActuatorStore(manualActuatorStore)
            let telemetry: (WorldStepLog) -> Void = { [weak self] step in
                self?.recordLiveStep(step)
            }
            command.setTelemetry(telemetry)
            modelContexts[model.id] = ModelContext(
                store: store,
                commandSystem: command
            )
        }

        if let first = persisted.first, let context = modelContexts[first.id] {
            selectedModelID = first.id
            activeModelID = first.id
            modelStore = context.store
            commandSystem = context.commandSystem
            loadSelectedModelIfAvailable()
        }
    }

    private func loadPersistedModels() -> [TrainingModelInfo] {
        checkpointStore.loadPersistedModels()
    }

    private func loadSelectedModelIfAvailable() {
        guard let selectedModel else { return }
        do {
            guard let manifest = try checkpointStore.load(model: selectedModel, into: modelStore) else { return }
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
        do {
            try checkpointStore.persist(model: selectedModel, from: modelStore)
            emitTerminal(level: .info, message: "Model saved", metadata: [
                "path": selectedModel.storageURL.path
            ])
        } catch {
            emitError("Model save failed", error: error)
        }
    }

    private func removeModelArtifacts(at url: URL) {
        for artifact in checkpointStore.removeArtifacts(at: url) {
            if let error = artifact.errorDescription {
                emitTerminal(level: .warning, message: "Failed to remove model artifact", metadata: [
                    "path": artifact.url.path,
                    "error": error
                ])
            }
        }
    }

    private func modelRootDirectory() -> URL {
        checkpointStore.rootDirectory()
    }

    private func modelDirectory(for id: UUID) -> URL {
        checkpointStore.modelDirectory(for: id)
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
        guard let presentation = telemetryPresenter.present(
            step: step,
            taskMode: taskMode,
            activeParameters: activeParameters,
            isActive: isRunning || isLoopRunning || isTraining
        ) else { return }

        liveSampleStride = presentation.liveSampleStride
        lastSensorSamples = presentation.sensorSamples
        lastActuatorValues = presentation.actuatorValues
        lastDriveIntents = presentation.driveIntents
        lastReflexCorrections = presentation.reflexCorrections
        lastActuatorTelemetry = presentation.actuatorTelemetry
        lastMotorNerveTrace = presentation.motorNerveTrace
        liveScene = presentation.sceneState

        if let strideLogMetadata = presentation.strideLogMetadata {
            emitTerminal(level: .info, message: "Render stride auto-set", metadata: strideLogMetadata)
        }
        if let stepLogMetadata = presentation.stepLogMetadata {
            emitTerminal(level: .notice, message: "Sim step", metadata: stepLogMetadata)
        }
    }

    private func resetLiveStride() {
        telemetryPresenter.resetStride()
        liveSampleStride = telemetryPresenter.liveSampleStride
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

    func descriptorDescendingChannelIDs() -> [String] {
        guard let descriptor = descriptorSnapshot()?.descriptor else { return [] }
        return descriptor.control.descendingChannels ?? []
    }

    func descendingSignalDefinitions() -> [RobotDescriptor.SignalDefinition] {
        guard let descriptor = descriptorSnapshot()?.descriptor else { return [] }
        let definitions = descriptor.signals.descending ?? []
        guard let descendingChannels = descriptor.control.descendingChannels,
              !descendingChannels.isEmpty else {
            return definitions.sorted { $0.index < $1.index }
        }
        return orderedSignals(ids: descendingChannels, from: definitions)
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

    private func resolvedDescendingIntent(
        controller: ControllerSelection,
        action: String
    ) throws -> ResolvedDescendingIntent {
        let resolution = try descendingIntentResolver.resolve(
            controller: controller,
            channelIDs: descriptorDescendingChannelIDs(),
            vectorText: descendingVectorText,
            programText: descendingProgramText
        )
        if let presentation = resolution.presentation {
            let level: Logger.Level = presentation.severity == .info ? .info : .warning
            emitUIAction(
                level: level,
                message: presentation.message,
                action: action,
                metadata: presentation.metadata
            )
        }
        return resolution.intent
    }

    private func orderedSignals(
        ids: [String],
        from definitions: [RobotDescriptor.SignalDefinition]
    ) -> [RobotDescriptor.SignalDefinition] {
        let map = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        return ids.compactMap { map[$0] }
    }

}
