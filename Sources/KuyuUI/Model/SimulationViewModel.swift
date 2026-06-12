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
    var taskMode: SimulationTaskMode = .lift {
        didSet {
            refreshManualActuatorLayout()
            emitUIAction(level: .info, message: "Task mode changed", action: "setTaskMode", metadata: [
                "value": taskMode.rawValue
            ])
            if oldValue != taskMode {
                invalidateLearningStarterProject(reason: "taskChanged")
            }
        }
    }

    var useEnvironmentConfig = false
    var logLevel: LogLevelOption = .info
    var logLabel: String = "kuyu.ui"
    var logDirectory: String = ""
    var trainingDatasetDirectory: String = ""
    var trainingInputDirectory: String = ""
    private(set) var robotManifestPath: String = KuyuUIModelPaths.defaultRobotManifestPath() {
        didSet {
            robotCachePath = nil
            robotCache = nil
            robotCacheError = nil
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
    private var robotCachePath: String?
    private var robotCache: LoadedKuyuRobot?
    private var robotCacheError: String?
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
    var learningCampaignExperimentName: String = "Drone Autonomy Starter"
    var learningCampaignExperimentDescription: String = "Ready-to-run hybrid GA/RL starter project for Manas lift control."
    var learningCampaignTagsText: String = "starter, drone, lift, hybrid"
    var learningCampaignTrainingStageID: String?
    var learningCampaignTrainingStageDisplayName: String?
    var learningCampaignTrainingStageKind: AutonomousTrainingStageKind?
    var learningCampaignPolicyContract: LearningProjectPolicyContract = ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract()
    var learningCampaignActionContract: LearningProjectActionContract = ReferenceQuadrotorLearningContracts.bodyRateActionContract()
    var learningStrategySelection: LearningStrategySelection = .hybrid
    var learningCampaignArtifactDirectory: String = ""
    var learningCampaignSourceCheckpointPath: String = ""
    var learningCampaignSuites: String = "6"
    var learningCampaignSeedCount: Int = 2
    var learningCampaignPopulation: Int = 100
    var learningCampaignGenerations: Int = 1_000
    var learningCampaignEliteCount: Int = 10
    var learningCampaignWorkers: Int = 2
    var learningCampaignCandidateEvaluationConcurrency: Int = 24
    var learningCampaignEpisodes: Int = 1
    var learningCampaignMutationRate: Double = 0.16
    var learningCampaignMutationNoiseScale: Double = 0.035
    var learningCampaignMinimumIncumbentImprovement: Double = 0
    var learningCampaignAdaptiveMutation: Bool = true
    var learningCampaignCompactRetention: Bool = true
    var learningCampaignAutoParallelism: Bool = true
    var learningCampaignRequiresInitialParentPass: Bool = false
    var learningCampaignMachineCapacity: LearningCampaignMachineCapacity = .current()
    var learningCampaignAutonomyDomain: AutonomousOperationDomain = .aerialDrone
    var learningCampaignPreset: LearningCampaignRunPreset = .convergence {
        didSet { applyLearningCampaignPreset(learningCampaignPreset) }
    }
    var learningStarterProjectStatus: String = "Preparing starter project"
    var isLearningStarterProjectReady: Bool = false
    var learningCampaignReadiness: LearningCampaignReadinessState = .idle
    var learningCampaignLaunchEstimate: LearningCampaignLaunchEstimate?
    var learningCampaignTemplateStatus: String?
    var learningCampaignQueuedRuns: [LearningCampaignQueuedRun] = []
    var learningCampaignProgressFraction: Double = 0
    var learningCampaignCurrentPhase: String = "idle"
    var learningCampaignLatestEvent: String?
    var learningCampaignRunLog: [LearningCampaignRunLogRecord] = []
    var learningCampaignLiveFitnessSamples: [MetricSample] = []
    var learningCampaignLiveRewardSamples: [MetricSample] = []
    var learningCampaignLiveTaskPassSamples: [MetricSample] = []
    var learningCampaignLiveHoldTimeSamples: [MetricSample] = []
    var learningCampaignLiveAltitudeErrorSamples: [MetricSample] = []
    var learningCampaignLiveEpisodeSamples: [MetricSample] = []
    var learningCampaignLiveCandidateEvaluationCount: Int = 0
    var learningCampaignLiveProgressEvents: [LearningCampaignProgressRecord] = []
    var learningCampaignProgressEventsForDisplay: [LearningCampaignProgressRecord] {
        let persisted = learningCampaignState?.progressEvents ?? []
        return (persisted + learningCampaignLiveProgressEvents).sorted { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        }
    }
    var isLearningCampaignRunning = false
    var learningCampaignMonitorEnabled = false
    var learningCampaignState: LearningCampaignRunStoreState?
    var learningCampaignError: String?
    var canContinueLearningCampaign: Bool {
        guard !isLearningCampaignRunning else { return false }
        return resumableLearningCampaignCheckpointURLIfAvailable() != nil
    }
    var learningCampaignContinuationCheckpointPath: String? {
        resumableLearningCampaignCheckpointURLIfAvailable()?.path
    }
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
    private let learningStarterProjectStore: LearningStarterProjectStore
    private let runnableProjectAssetPreparer: any RunnableProjectAssetPreparing
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
    private var learningCampaignArtifactLoadTask: Task<Void, Never>?
    private var learningCampaignArtifactLoadID: UInt64 = 0
    private var learningCampaignHandle: (any TrainingRunHandle)?
    private var learningCampaignContinuationSourceArtifactRoot: URL?
    var availableModels: [TrainingModelInfo] = []
    private var activeModelID: UUID?
    var selectedModelID: UUID?
    private var activeParameters: ReferenceQuadrotorParameters?
    private var starterProjectPreparationTask: Task<Void, Never>?
    private var isPreviewEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    public init(
        logStore: UILogStore,
        commandSystem: CommandSystem? = nil,
        learningStarterProjectStore: LearningStarterProjectStore = LearningStarterProjectStore(),
        runnableProjectAssetPreparer: (any RunnableProjectAssetPreparing)? = nil,
        prepareStarterProjectOnInit: Bool = false
    ) {
        self.logStore = logStore
        self.learningStarterProjectStore = learningStarterProjectStore
        let store = ManasMLXModelStore()
        self.modelStore = store
        self.runnableProjectAssetPreparer = runnableProjectAssetPreparer ?? ManasMLXRunnableProjectAssetPreparer(modelStore: store)
        self.commandSystem = commandSystem ?? CommandSystem(modelStore: store)
        self.logger = Logger(label: "kuyu.ui")
        self.logger.logLevel = .info

        let telemetry: WorldStepTelemetry = { [weak self] step in
            Task { @MainActor in
                self?.recordLiveStep(step)
            }
        }
        self.commandSystem.setTelemetry(telemetry)
        self.commandSystem.setManualActuatorStore(manualActuatorStore)
        manualActuatorStore.isEnabled = manualActuatorEnabled
        manualActuatorStore.update(values: manualActuatorValues)
        refreshManualActuatorLayout()
        manualActuatorMaster = manualActuatorValues.first ?? 0.0
        installLogObserverIfNeeded()

        loadPersistedModelsOrFallback(defaultStore: store)
        if prepareStarterProjectOnInit && !isPreviewEnvironment {
            scheduleStarterLearningProjectPreparation()
        } else {
            learningStarterProjectStatus = "Starter project not prepared"
            isLearningStarterProjectReady = false
        }
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
        if currentRobotIsArticulatedDynamic() {
            let robotID = robotCache?.manifest.robotID ?? "articulated"
            return [
                "suite": "\(robotID.uppercased())-DYN-1",
                "motorNerveProfile": motorNerveProfile
            ]
        }
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
        guard !currentRobotIsArticulatedDynamic() else { return }
        guard !RobotManifestSelection.isRoArmM1RobotManifestPath(modelPath) else { return }
        if taskMode == .singleLift && RobotManifestSelection.isQuadRobotManifestPath(modelPath) {
            emitUIAction(level: .warning, message: "Single Lift task using quad robot manifest", action: "taskRobotManifestMismatch", metadata: [
                "path": modelPath,
                "reason": "singleLiftUsesQuad"
            ])
        }
        if taskMode != .singleLift && RobotManifestSelection.isSinglePropRobotManifestPath(modelPath) {
            emitUIAction(level: .warning, message: "Quad task using single-prop robot manifest", action: "taskRobotManifestMismatch", metadata: [
                "path": modelPath,
                "reason": "quadUsesSingleProp"
            ])
        }
    }

    private func isQuadRobotManifestPath(_ path: String) -> Bool {
        RobotManifestSelection.isQuadRobotManifestPath(path)
    }

    private func isSinglePropRobotManifestPath(_ path: String) -> Bool {
        RobotManifestSelection.isSinglePropRobotManifestPath(path)
    }

    private func currentRobotIsArticulatedDynamic() -> Bool {
        if RobotManifestSelection.isRoArmM1RobotManifestPath(robotManifestPath) {
            return true
        }
        guard let loaded = robotCache else { return false }
        let movableJointCount = loaded.body.joints.filter {
            $0.kind == .revolute || $0.kind == .continuous || $0.kind == .prismatic
        }.count
        return (loaded.manifest.category == "manipulator" || loaded.body.category == "manipulator")
            && movableJointCount > 0
    }

    private func desiredRobotManifestPath(for task: SimulationTaskMode) -> String {
        RobotManifestSelection.desiredRobotManifestPath(for: task)
    }

    private func ensureRobotManifestForTask(reason: String) -> String {
        let resolution = RobotManifestSelection.resolveForTask(
            configuredPath: robotManifestPath,
            taskMode: taskMode
        )
        if resolution.didSwitch && resolution.reason == "emptyPath" {
            robotManifestPath = resolution.path
            emitUIAction(level: .info, message: "Robot manifest set for task", action: "robotManifestAutoSet", metadata: [
                "reason": reason,
                "path": resolution.path
            ])
            return resolvedRobotManifestPath()
        }

        if resolution.didSwitch && resolution.reason == "singleLiftUsesQuad" {
            let previous = robotManifestPath.trimmingCharacters(in: .whitespacesAndNewlines)
            robotManifestPath = resolution.path
            emitUIAction(level: .warning, message: "Robot manifest auto-switched for Single Lift task", action: "robotManifestAutoSwitch", metadata: [
                "reason": reason,
                "from": previous,
                "to": resolution.path
            ])
        } else if resolution.didSwitch && resolution.reason == "quadUsesSingleProp" {
            let previous = robotManifestPath.trimmingCharacters(in: .whitespacesAndNewlines)
            robotManifestPath = resolution.path
            emitUIAction(level: .warning, message: "Robot manifest auto-switched for quad task", action: "robotManifestAutoSwitch", metadata: [
                "reason": reason,
                "from": previous,
                "to": resolution.path
            ])
        }

        return resolvedRobotManifestPath()
    }

    private func emitObjectiveWarningIfNeeded() {
        guard !currentRobotIsArticulatedDynamic() else { return }
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
        let telemetry: WorldStepTelemetry = { [weak self] step in
            Task { @MainActor in
                self?.recordLiveStep(step)
            }
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
        let telemetry: WorldStepTelemetry = { [weak self] step in
            Task { @MainActor in
                self?.recordLiveStep(step)
            }
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
        if taskMode != .singleLift && !currentRobotIsArticulatedDynamic() {
            emitUIAction(level: .warning, message: "Run auto-switched to Single Lift task", action: "runBaseline", metadata: [
                "fromTask": taskMode.rawValue,
                "toTask": SimulationTaskMode.singleLift.rawValue,
                "reason": "baselineRequiresSingleLift"
            ])
            taskMode = .singleLift
        }
        let resolvedPath = ensureRobotManifestForTask(reason: "runBaseline")
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
            effectiveController = .teacherActiveAltitudeHold
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
            robotManifestPath: resolvedPath,
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
                guard case .trainingCompleted(let output) = result else {
                    isTraining = false
                    emitUIAction(level: .error, message: "Training returned an unexpected result", action: "trainCoreModel", metadata: [
                        "result": "\(result)"
                    ])
                    return
                }
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

        let resolvedPath = ensureRobotManifestForTask(reason: "startTrainingLoop")
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
                robotManifestPath: resolvedPath,
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
                "controller": "activeAltitudeHold",
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

    func prepareStarterLearningProject() {
        starterProjectPreparationTask?.cancel()
        prepareStarterLearningProjectNow(forceNewArtifactRoot: true)
    }

    private func prepareStarterLearningProjectNow(forceNewArtifactRoot: Bool) {
        do {
            let project = try prepareStarterLearningProjectIfNeeded(forceNewArtifactRoot: forceNewArtifactRoot)
            learningCampaignSourceCheckpointPath = project.sourceCheckpoint.path
            learningCampaignArtifactDirectory = project.artifactRoot.path
            learningStarterProjectStatus = "Ready: \(project.projectRoot.lastPathComponent)"
            isLearningStarterProjectReady = true
            learningCampaignReadiness = .idle
            learningCampaignError = nil
            estimateLearningCampaignCost()
            emitUIAction(level: .notice, message: "Starter learning project prepared", action: "prepareStarterLearningProject", metadata: [
                "sourceCheckpoint": project.sourceCheckpoint.path,
                "artifactRoot": project.artifactRoot.path
            ])
        } catch {
            learningStarterProjectStatus = "\(error)"
            isLearningStarterProjectReady = false
            learningCampaignError = "\(error)"
            learningCampaignReadiness = .blocked(message: "\(error)")
            emitUIAction(level: .error, message: "Starter learning project preparation failed", action: "prepareStarterLearningProject", metadata: [
                "error": "\(error)"
            ])
        }
    }

    private func scheduleStarterLearningProjectPreparation() {
        starterProjectPreparationTask?.cancel()
        learningStarterProjectStatus = "Preparing starter project"
        isLearningStarterProjectReady = false
        starterProjectPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            self.prepareStarterLearningProjectNow(forceNewArtifactRoot: false)
        }
    }

    func prepareNewLearningCampaignArtifactRoot() {
        do {
            let root = try learningStarterProjectStore.makeNextRunArtifactRoot()
            learningCampaignArtifactDirectory = root.path
            emitUIAction(level: .info, message: "Learning campaign artifact root prepared", action: "prepareLearningCampaignArtifactRoot", metadata: [
                "path": learningCampaignArtifactDirectory
            ])
        } catch {
            learningCampaignError = "\(error)"
            learningCampaignReadiness = .blocked(message: "\(error)")
            emitUIAction(level: .warning, message: "Learning campaign artifact root preparation failed", action: "prepareLearningCampaignArtifactRoot", metadata: [
                "error": "\(error)"
            ])
        }
    }

    func configureForProjectPackage(_ package: KuyuProjectPackage) {
        applyProjectTemplate(package.selectedTemplate)
        let starterDefaults = runnableStarterCampaignDefaults(for: package)
        learningCampaignTrainingStageID = starterDefaults.stageID
        learningCampaignTrainingStageDisplayName = starterDefaults.stageDisplayName
        learningCampaignTrainingStageKind = starterDefaults.stageKind
        learningCampaignExperimentName = package.defaultExperiment.name
        learningCampaignExperimentDescription = package.defaultExperiment.summary
        learningCampaignTagsText = package.defaultExperiment.tags.joined(separator: ", ")
        learningCampaignSuites = starterDefaults.suiteIDs
            .map(String.init)
            .joined(separator: ",")
        learningCampaignSeedCount = starterDefaults.seedCount
        learningCampaignPopulation = starterDefaults.populationSize
        learningCampaignGenerations = starterDefaults.generationLimit
        learningCampaignEliteCount = package.defaultExperiment.curriculum.eliteCount
        learningCampaignWorkers = package.defaultExperiment.compute.workerCount
        learningCampaignCandidateEvaluationConcurrency = max(
            24,
            package.defaultExperiment.compute.candidateEvaluationConcurrency
        )
        learningCampaignEpisodes = starterDefaults.episodesPerSuite
        learningCampaignAutonomyDomain = package.defaultExperiment.domain

        let sourceURL = package.rootURL.appendingPathComponent(
            package.sourceBundleReference.url,
            isDirectory: true
        )
        learningCampaignSourceCheckpointPath = sourceURL.path
        do {
            learningCampaignArtifactDirectory = try makeProjectRunArtifactRoot(in: package.rootURL).path
            learningCampaignError = nil
            learningCampaignReadiness = .idle
        } catch {
            learningCampaignError = "\(error)"
            learningCampaignReadiness = .blocked(message: "\(error)")
        }
        do {
            if let latestRun = try latestProjectRunArtifactRoot(in: package.rootURL) {
                learningCampaignArtifactDirectory = latestRun.path
                loadLearningCampaignArtifacts()
            }
        } catch {
            emitUIAction(level: .warning, message: "Latest project run unavailable", action: "loadLatestProjectRun", metadata: [
                "project": package.rootURL.path,
                "error": "\(error)"
            ])
        }

        let sourceIsCompleteForTemplate = learningStarterProjectStore.checkpointIsComplete(
            at: sourceURL,
            policyContract: package.selectedTemplate.policy
        )
        let sourceIsValidForTemplate = sourceIsCompleteForTemplate && starterSourceCheckpointIsValid(
            at: sourceURL,
            robotManifestPath: ensureRobotManifestForTask(reason: "kuyuProjectOpen"),
            policyContract: package.selectedTemplate.policy,
            actionContract: package.selectedTemplate.action
        )

        if !package.selectedTemplate.isRunnableStarter {
            isLearningStarterProjectReady = false
            learningStarterProjectStatus = "Template runtime is not implemented yet"
        } else if sourceIsValidForTemplate {
            isLearningStarterProjectReady = true
            learningStarterProjectStatus = "Ready: \(package.rootURL.lastPathComponent)"
        } else if sourceIsCompleteForTemplate {
            isLearningStarterProjectReady = false
            learningStarterProjectStatus = "Starter checkpoint incompatible"
        } else {
            isLearningStarterProjectReady = false
            learningStarterProjectStatus = "Starter checkpoint missing"
        }

        estimateLearningCampaignCost()
        emitUIAction(level: .notice, message: "Kuyu project opened", action: "openKuyuProject", metadata: [
            "project": package.rootURL.path,
            "template": package.selectedTemplate.templateID
        ])
    }

    func prepareRunnableProjectAssets(for package: KuyuProjectPackage) throws {
        guard package.selectedTemplate.isRunnableStarter else {
            throw LearningCampaignLaunchError.invalidConfiguration("Template runtime is not implemented: \(package.selectedTemplate.task)")
        }

        applyProjectTemplate(package.selectedTemplate)
        let sourceURL = package.rootURL.appendingPathComponent(
            package.sourceBundleReference.url,
            isDirectory: true
        )
        let robotManifestPath = ensureRobotManifestForTask(reason: "kuyuProject")
        let observationTaskMode = taskMode
        try runnableProjectAssetPreparer.prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest(
            checkpointURL: sourceURL,
            displayName: package.manifest.name,
            robotManifestPath: robotManifestPath,
            embodiment: currentEmbodiment(),
            taskMode: observationTaskMode,
            driveCount: package.selectedTemplate.action.driveCount,
            expectedDriveCount: starterExpectedDriveCount(for: observationTaskMode),
            expectedObservationChannelCount: package.selectedTemplate.observation.channelCount,
            auxEnabled: trainingUseAux,
            qualityGatingEnabled: trainingUseQualityGating,
            policyContract: package.selectedTemplate.policy,
            actionContract: package.selectedTemplate.action
        ))

        learningCampaignSourceCheckpointPath = sourceURL.path
        learningCampaignArtifactDirectory = try makeProjectRunArtifactRoot(in: package.rootURL).path
        isLearningStarterProjectReady = true
        learningStarterProjectStatus = "Ready: \(package.rootURL.lastPathComponent)"
        learningCampaignReadiness = .idle
        learningCampaignError = nil
        estimateLearningCampaignCost()
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
            let request = try makeTrainingRunRequest(
                runID: TrainingRunID("validation-\(UUID().uuidString)"),
                prepareMissingInputs: true
            )
            try commandSystem.validateLearningCampaign(request: request)
            learningCampaignLaunchEstimate = makeLearningCampaignLaunchEstimate(
                suites: request.configuration.scenarioSelection.suiteIDs
            )
            learningCampaignReadiness = .ready(message: "Source checkpoint, embodiment, suites, and artifact root are valid.")
            learningCampaignError = nil
            emitUIAction(level: .notice, message: "Learning campaign dry validation passed", action: "validateLearningCampaign", metadata: [
                "task": request.taskProfileID,
                "artifactRoot": request.artifactRoot.path,
                "sourceCheckpoint": request.sourceBundle?.url.path ?? ""
            ])
        } catch {
            learningCampaignReadiness = .blocked(message: "\(error)")
            learningCampaignError = "\(error)"
            emitUIAction(level: .warning, message: "Learning campaign dry validation failed", action: "validateLearningCampaign", metadata: [
                "error": "\(error)"
            ])
        }
    }

    private func runnableStarterCampaignDefaults(
        for package: KuyuProjectPackage
    ) -> (
        stageID: String?,
        stageDisplayName: String?,
        stageKind: AutonomousTrainingStageKind?,
        suiteIDs: [Int],
        seedCount: Int,
        populationSize: Int,
        generationLimit: Int,
        episodesPerSuite: Int
    ) {
        guard package.selectedTemplate.isRunnableStarter,
              let stage = package.selectedTemplate.primaryRunnableTrainingStage else {
            let curriculum = package.defaultExperiment.curriculum
            return (
                stageID: nil,
                stageDisplayName: nil,
                stageKind: nil,
                suiteIDs: curriculum.suiteIDs,
                seedCount: curriculum.seedCount,
                populationSize: curriculum.populationSize,
                generationLimit: curriculum.generationLimit,
                episodesPerSuite: curriculum.episodesPerSuite
            )
        }

        if package.selectedTemplate.templateID == "aerial-drone-autonomy-starter-v1",
           stage.task == "lift" {
            return (
                stageID: stage.stageID,
                stageDisplayName: stage.displayName,
                stageKind: stage.kind,
                suiteIDs: [6],
                seedCount: max(2, stage.seedCount),
                populationSize: package.defaultExperiment.curriculum.populationSize,
                generationLimit: stage.generationLimit,
                episodesPerSuite: stage.episodesPerSuite
            )
        }

        return (
            stageID: stage.stageID,
            stageDisplayName: stage.displayName,
            stageKind: stage.kind,
            suiteIDs: stage.suiteIDs,
            seedCount: stage.seedCount,
            populationSize: package.defaultExperiment.curriculum.populationSize,
            generationLimit: stage.generationLimit,
            episodesPerSuite: stage.episodesPerSuite
        )
    }

    func estimateLearningCampaignCost() {
        do {
            let suites = try learningCampaignSuiteValues()
            if learningCampaignAutoParallelism {
                applyLearningCampaignParallelismRecommendation(suites: suites)
            }
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

    func optimizeLearningCampaignParallelismForMachine() {
        do {
            let suites = try learningCampaignSuiteValues()
            applyLearningCampaignParallelismRecommendation(suites: suites)
            learningCampaignLaunchEstimate = makeLearningCampaignLaunchEstimate(suites: suites)
            learningCampaignError = nil
            emitUIAction(level: .notice, message: "Learning campaign parallelism optimized", action: "optimizeLearningCampaignParallelism", metadata: [
                "machine": learningCampaignMachineCapacity.summary,
                "workers": "\(learningCampaignWorkers)",
                "candidateEvaluationConcurrency": "\(learningCampaignCandidateEvaluationConcurrency)"
            ])
        } catch {
            learningCampaignError = "\(error)"
            learningCampaignReadiness = .blocked(message: "\(error)")
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

        let request: TrainingRunRequest
        let continuationArtifactRoot: URL?
        do {
            continuationArtifactRoot = learningCampaignContinuationSourceArtifactRoot
            request = try makeTrainingRunRequest(
                runID: TrainingRunID("ui-\(UUID().uuidString)"),
                prepareMissingInputs: true
            )
            let configuration = request.configuration
            let suites = configuration.scenarioSelection.suiteIDs
            isLearningCampaignRunning = true
            learningCampaignError = nil
            learningCampaignLaunchEstimate = makeLearningCampaignLaunchEstimate(suites: suites)
            learningCampaignReadiness = .ready(message: "Campaign launched with validated config.")
            learningCampaignProgressFraction = 0
            learningCampaignCurrentPhase = "starting"
            learningCampaignLatestEvent = nil
            learningCampaignRunLog = [
                LearningCampaignRunLogRecord(
                    category: .lifecycle,
                    phase: "starting",
                    title: "Campaign launch requested",
                    detail: "stage \(configuration.trainingStageDisplayName ?? configuration.trainingStageID ?? "unscoped"), task \(request.taskProfileID), suites \(suites.map(String.init).joined(separator: ",")), seeds \(request.seedCount), population \(request.populationSize), generations \(request.generationLimit ?? 0)",
                    metadata: ["artifact \(request.artifactRoot.path)"]
                )
            ]
            resetLearningCampaignLiveMetricSamples()
            startLearningCampaignMonitoring()
            emitUIAction(level: .notice, message: "Learning campaign started", action: "startLearningCampaign", metadata: [
                "task": request.taskProfileID,
                "stage": configuration.trainingStageID ?? "unscoped",
                "artifactRoot": request.artifactRoot.path,
                "sourceCheckpoint": request.sourceBundle?.url.path ?? "",
                "seedCount": "\(request.seedCount)",
                "population": "\(request.populationSize)",
                "generations": "\(request.generationLimit ?? 0)"
            ])
            learningCampaignContinuationSourceArtifactRoot = nil
        } catch {
            learningCampaignContinuationSourceArtifactRoot = nil
            isLearningCampaignRunning = false
            learningCampaignError = "\(error)"
            learningCampaignReadiness = .blocked(message: "\(error)")
            emitUIAction(level: .error, message: "Learning campaign launch failed", action: "startLearningCampaign", metadata: [
                "error": "\(error)"
            ])
            return
        }

        learningCampaignWaitTask?.cancel()
        learningCampaignWaitTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                let handle: any TrainingRunHandle
                if let continuationArtifactRoot {
                    handle = try await self.commandSystem.resumeTrainingRun(request: TrainingResumeRequest(
                        runID: request.runID,
                        source: .artifactRoot(continuationArtifactRoot),
                        destinationArtifactRoot: request.artifactRoot,
                        projectRoot: request.projectRoot,
                        taskProfileID: request.taskProfileID,
                        policyContract: request.policyContract,
                        actionContract: request.actionContract,
                        seedCount: request.seedCount,
                        populationSize: request.populationSize,
                        generationLimit: request.generationLimit,
                        configuration: request.configuration
                    ))
                } else {
                    handle = try await self.commandSystem.startTrainingRun(request: request)
                }
                // A stop issued while the backend was still launching cancels this
                // task; the freshly created handle must be cancelled, not adopted.
                guard !Task.isCancelled else {
                    handle.cancel()
                    return
                }
                self.learningCampaignHandle = handle
                self.learningCampaignProgressFraction = handle.progress.fractionCompleted
                self.startLearningCampaignEventMonitoring(handle: handle)
            } catch {
                self?.learningCampaignHandle = nil
                self?.isLearningCampaignRunning = false
                self?.learningCampaignError = "\(error)"
                self?.learningCampaignReadiness = .blocked(message: "\(error)")
                self?.learningCampaignCurrentPhase = "failed"
                self?.emitUIAction(level: .error, message: "Learning campaign launch failed", action: "startLearningCampaign", metadata: [
                    "error": "\(error)"
                ])
            }
        }
    }

    func continueLearningCampaignFromLastCheckpoint() {
        if isLearningCampaignRunning || learningCampaignHandle != nil {
            emitUIAction(level: .warning, message: "Learning campaign already running", action: "continueLearningCampaign")
            return
        }

        do {
            loadLearningCampaignArtifacts()
            let previousArtifactURL = try currentLearningCampaignArtifactURL()
            let selection = try commandSystem.learningCampaignContinuationSelection(from: previousArtifactURL)
            let checkpointURL = selection.checkpointURL
            let nextArtifactURL = try makeSiblingRunArtifactRoot(after: previousArtifactURL)
            learningCampaignSourceCheckpointPath = checkpointURL.path
            learningCampaignArtifactDirectory = nextArtifactURL.path
            learningCampaignContinuationSourceArtifactRoot = previousArtifactURL
            learningCampaignState = nil
            learningCampaignProgressFraction = 0
            learningCampaignCurrentPhase = "continuing"
            learningCampaignLatestEvent = "Continuing from \(checkpointURL.lastPathComponent)"
            learningCampaignRunLog = [
                LearningCampaignRunLogRecord(
                    category: .lifecycle,
                    phase: "continuing",
                    title: "Continue requested",
                    detail: "Continuing search from \(selection.source.rawValue) checkpoint \(checkpointURL.lastPathComponent)",
                    metadata: [
                        "previous artifact \(previousArtifactURL.path)",
                        "source \(checkpointURL.path)",
                        "artifact \(nextArtifactURL.path)"
                    ]
                )
            ]
            emitUIAction(level: .notice, message: "Learning campaign continuation prepared", action: "continueLearningCampaign", metadata: [
                "sourceCheckpoint": checkpointURL.path,
                "artifactRoot": nextArtifactURL.path,
                "previousArtifactRoot": previousArtifactURL.path,
                "selectionSource": selection.source.rawValue
            ])
            startLearningCampaign()
        } catch {
            learningCampaignError = "\(error)"
            learningCampaignReadiness = .blocked(message: "\(error)")
            emitUIAction(level: .error, message: "Learning campaign continuation failed", action: "continueLearningCampaign", metadata: [
                "error": "\(error)"
            ])
        }
    }

    func stopLearningCampaign() {
        learningCampaignWaitTask?.cancel()
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
        learningCampaignArtifactLoadID &+= 1
        let loadID = learningCampaignArtifactLoadID
        learningCampaignArtifactLoadTask?.cancel()
        learningCampaignArtifactLoadTask = Task { [weak self, directory, loadID] in
            do {
                let state = try await Task.detached(priority: .utility) {
                    try LearningCampaignRunStore().load(from: directory)
                }.value
                try Task.checkCancellation()
                await MainActor.run {
                    self?.applyLearningCampaignArtifactLoad(
                        state: state,
                        directory: directory,
                        loadID: loadID
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.applyLearningCampaignArtifactLoadFailure(
                        error: error,
                        directory: directory,
                        loadID: loadID
                    )
                }
            }
        }
    }

    func waitForLearningCampaignArtifactLoad() async {
        await learningCampaignArtifactLoadTask?.value
    }

    private func applyLearningCampaignArtifactLoad(
        state: LearningCampaignRunStoreState,
        directory: URL,
        loadID: UInt64
    ) {
        guard loadID == learningCampaignArtifactLoadID else { return }
        learningCampaignState = state
        learningCampaignProgressFraction = state.campaignProgressFraction
        learningCampaignError = nil
        isLearningCampaignRunning = learningCampaignHandle != nil
        if learningCampaignHandle == nil {
            learningCampaignRunLog = LearningCampaignRunLogFormatter.entries(from: state)
            learningCampaignCurrentPhase = state.isActive ? "stale \(state.statusLabel)" : state.statusLabel
        }
        learningCampaignArtifactLoadTask = nil
    }

    private func applyLearningCampaignArtifactLoadFailure(
        error: any Error,
        directory: URL,
        loadID: UInt64
    ) {
        guard loadID == learningCampaignArtifactLoadID else { return }
        learningCampaignError = "\(error)"
        isLearningCampaignRunning = learningCampaignHandle != nil
        learningCampaignArtifactLoadTask = nil
        emitTerminal(level: .warning, message: "Learning campaign artifacts unavailable", metadata: [
            "path": directory.path,
            "error": "\(error)"
        ])
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

    private func startLearningCampaignEventMonitoring(handle: any TrainingRunHandle) {
        learningCampaignEventTask?.cancel()
        learningCampaignEventTask = Task { @MainActor [weak self, handle] in
            for await event in handle.events {
                self?.applyTrainingRunEvent(event, progress: handle.progress)
            }
            guard !Task.isCancelled else { return }
            guard self?.learningCampaignHandle?.runID == handle.runID else { return }
            self?.learningCampaignHandle = nil
            self?.learningCampaignEventTask = nil
            self?.learningCampaignWaitTask = nil
            self?.isLearningCampaignRunning = false
            if self?.learningCampaignCurrentPhase != "cancelled" {
                self?.learningCampaignProgressFraction = max(
                    self?.learningCampaignProgressFraction ?? 0,
                    handle.progress.fractionCompleted
                )
            }
            self?.loadLearningCampaignArtifacts()
        }
    }

    private func applyTrainingRunEvent(
        _ event: TrainingRunEvent,
        progress: Progress
    ) {
        learningCampaignProgressFraction = boundedLearningCampaignProgress(progress.fractionCompleted)
        switch event {
        case .progress(let progressEvent):
            applyTrainingRunProgressEvent(progressEvent)
        case .log(let logEvent):
            applyTrainingRunLogEvent(logEvent, progress: progress)
        case .started(let manifest):
            learningCampaignCurrentPhase = "started"
            learningCampaignLatestEvent = "Run \(manifest.runID) started"
            appendLearningCampaignRunLogRecord(
                LearningCampaignRunLogFormatter.entry(from: TrainingRunLogEvent(
                    level: .info,
                    phase: "started",
                    message: "Training run started",
                    metadata: ["runID": manifest.runID]
                ), progress: progress)
            )
        case .iterationStarted(let iteration):
            learningCampaignCurrentPhase = "iteration \(iteration)"
            learningCampaignLatestEvent = "Iteration \(iteration) started"
        case .suiteCompleted(let iteration, _, let score):
            learningCampaignCurrentPhase = "iteration \(iteration)"
            learningCampaignLatestEvent = String(format: "Suite score %.3f", score)
        case .datasetExported(let iteration, let directory, let count):
            learningCampaignCurrentPhase = "dataset"
            learningCampaignLatestEvent = "Iteration \(iteration) exported \(count) samples"
            appendLearningCampaignRunLogRecord(
                LearningCampaignRunLogFormatter.entry(from: TrainingRunLogEvent(
                    level: .info,
                    phase: "dataset",
                    message: "Dataset exported",
                    metadata: ["iteration": "\(iteration)", "directory": directory, "count": "\(count)"]
                ), progress: progress)
            )
        case .trainingCompleted(let iteration, let result):
            learningCampaignCurrentPhase = "training"
            learningCampaignLatestEvent = String(format: "Iteration \(iteration) loss %.6f", result.finalLoss)
        case .reinforcementTrainingCompleted(let iteration, let result):
            learningCampaignCurrentPhase = "reinforcement"
            learningCampaignLatestEvent = String(format: "Iteration \(iteration) reward %.3f", result.rewardAverage)
        case .convergenceUpdated(let summary):
            learningCampaignCurrentPhase = "convergence"
            learningCampaignLatestEvent = summary.accepted ? "Checkpoint accepted" : summary.reason
        case .completed(let result):
            learningCampaignCurrentPhase = result.manifest.terminalState.rawValue
            learningCampaignLatestEvent = result.checkpointDecision.state.rawValue
        }
    }

    private func applyTrainingRunLogEvent(
        _ logEvent: TrainingRunLogEvent,
        progress: Progress
    ) {
        appendLearningCampaignRunLogRecord(
            LearningCampaignRunLogFormatter.entry(from: logEvent, progress: progress)
        )
        learningCampaignCurrentPhase = logEvent.phase
        learningCampaignLatestEvent = logEvent.message
    }

    private func applyTrainingRunProgressEvent(_ progressEvent: TrainingRunProgressEvent) {
        appendLearningCampaignLiveProgressEvent(progressEvent)
        if let progressFraction = progressEvent.progressFraction {
            learningCampaignProgressFraction = boundedLearningCampaignProgress(progressFraction)
        }
        if let phase = progressEvent.phase {
            learningCampaignCurrentPhase = phase
        }
        if let message = progressEvent.message {
            learningCampaignLatestEvent = message
        }
    }

    private func boundedLearningCampaignProgress(_ fallback: Double) -> Double {
        if let state = learningCampaignState {
            return state.campaignProgressFraction
        }
        return min(0.999, max(0, fallback))
    }

    private func appendLearningCampaignRunLogRecord(_ entry: LearningCampaignRunLogRecord) {
        learningCampaignRunLog.append(entry)
        let maximumEntryCount = 500
        if learningCampaignRunLog.count > maximumEntryCount {
            learningCampaignRunLog.removeFirst(learningCampaignRunLog.count - maximumEntryCount)
        }
    }

    private func resetLearningCampaignLiveMetricSamples() {
        learningCampaignLiveFitnessSamples = []
        learningCampaignLiveRewardSamples = []
        learningCampaignLiveTaskPassSamples = []
        learningCampaignLiveHoldTimeSamples = []
        learningCampaignLiveAltitudeErrorSamples = []
        learningCampaignLiveEpisodeSamples = []
        learningCampaignLiveCandidateEvaluationCount = 0
        learningCampaignLiveProgressEvents = []
    }

    func appendLearningCampaignLiveProgressEvent(_ progressEvent: TrainingRunProgressEvent) {
        let progressRecord = makeLearningCampaignProgressRecord(from: progressEvent)
        learningCampaignLiveProgressEvents.append(progressRecord)
        let maximumEntryCount = 1_000
        if learningCampaignLiveProgressEvents.count > maximumEntryCount {
            learningCampaignLiveProgressEvents.removeFirst(learningCampaignLiveProgressEvents.count - maximumEntryCount)
        }
        appendLearningCampaignLiveMetricSamples(progressRecord)
    }

    private func makeLearningCampaignProgressRecord(
        from progressEvent: TrainingRunProgressEvent
    ) -> LearningCampaignProgressRecord {
        return LearningCampaignProgressRecord(
            event: progressEvent.event,
            timestamp: ISO8601DateFormatter().string(from: progressEvent.timestamp),
            status: progressEvent.status,
            exitCode: progressEvent.exitCode,
            phase: progressEvent.phase,
            seed: progressEvent.seed,
            generationIndex: progressEvent.generationIndex,
            candidateID: progressEvent.candidateID,
            fitness: progressEvent.fitness,
            rewardAverage: progressEvent.rewardAverage,
            taskPassRate: progressEvent.taskPassRate,
            safetyViolationRate: progressEvent.safetyViolationRate,
            holdTimeRatio: progressEvent.holdTimeRatio,
            altitudeErrorRatio: progressEvent.altitudeErrorRatio,
            workerThroughput: progressEvent.workerThroughput,
            gpuAcceleration: progressEvent.gpuAcceleration,
            tensorWorldBatch: progressEvent.tensorWorldBatch,
            tensorSummary: progressEvent.tensorSummary,
            vectorizedPopulationSize: progressEvent.vectorizedPopulationSize,
            vectorizedWorldCount: progressEvent.vectorizedWorldCount,
            vectorizedHistoryLength: progressEvent.vectorizedHistoryLength,
            vectorizedObservationDimension: progressEvent.vectorizedObservationDimension,
            vectorizedActionDimension: progressEvent.vectorizedActionDimension,
            failureReasons: progressEvent.failureReasons,
            bestCandidateID: progressEvent.bestCandidateID,
            accepted: progressEvent.accepted,
            path: progressEvent.path,
            message: progressEvent.message
        )
    }

    func appendLearningCampaignLiveMetricSamples(_ fitness: FitnessSummary) {
        learningCampaignLiveCandidateEvaluationCount += 1
        let time = Double(fitness.generationIndex)

        let replacesGenerationBest = shouldReplaceGenerationBest(
            generationIndex: fitness.generationIndex,
            scalarFitness: fitness.scalarFitness
        )
        if replacesGenerationBest {
            upsertMetricSample(MetricSample(time: time, value: fitness.scalarFitness), in: &learningCampaignLiveFitnessSamples)
            upsertMetricSample(MetricSample(time: time, value: fitness.rewardAverage), in: &learningCampaignLiveRewardSamples)
            upsertMetricSample(MetricSample(time: time, value: fitness.taskPassRate), in: &learningCampaignLiveTaskPassSamples)
        }
        if let holdTimeRatio = fitness.holdTimeRatio {
            if replacesGenerationBest {
                upsertMetricSample(MetricSample(time: time, value: holdTimeRatio), in: &learningCampaignLiveHoldTimeSamples)
            }
        }
        if let altitudeErrorRatio = fitness.altitudeErrorRatio {
            if replacesGenerationBest {
                upsertMetricSample(MetricSample(time: time, value: altitudeErrorRatio), in: &learningCampaignLiveAltitudeErrorSamples)
            }
        }
        let suiteCount = learningCampaignSuites
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        let episodeMultiplier = max(1, learningCampaignEpisodes * max(1, suiteCount))
        upsertMetricSample(
            MetricSample(time: time, value: Double(learningCampaignLiveCandidateEvaluationCount * episodeMultiplier)),
            in: &learningCampaignLiveEpisodeSamples
        )
    }

    private func appendLearningCampaignLiveMetricSamples(_ progressRecord: LearningCampaignProgressRecord) {
        guard progressRecord.event == "candidate-evaluated",
              let generationIndex = progressRecord.generationIndex,
              let candidateID = progressRecord.candidateID,
              let fitness = progressRecord.fitness,
              let rewardAverage = progressRecord.rewardAverage else {
            return
        }
        let summary = FitnessSummary(
            runID: progressRecord.seed ?? "live",
            generationIndex: generationIndex,
            candidateID: candidateID,
            taskID: learningCampaignTask().rawValue,
            scalarFitness: fitness,
            rewardAverage: rewardAverage,
            taskPassRate: progressRecord.taskPassRate ?? 0,
            safetyViolationRate: progressRecord.safetyViolationRate ?? 0,
            holdTimeRatio: progressRecord.holdTimeRatio,
            altitudeErrorRatio: progressRecord.altitudeErrorRatio,
            behaviorDescriptor: [
                "evaluation.gpu": progressRecord.gpuAcceleration == true ? 1 : 0,
                "evaluation.worldTensorBatch": progressRecord.tensorWorldBatch == true ? 1 : 0,
                "evaluation.tensorSummary": progressRecord.tensorSummary == true ? 1 : 0,
                "vectorized.populationSize": Double(progressRecord.vectorizedPopulationSize ?? 0),
                "vectorized.worldCount": Double(progressRecord.vectorizedWorldCount ?? 0),
                "vectorized.historyLength": Double(progressRecord.vectorizedHistoryLength ?? 0),
                "vectorized.observationDimension": Double(progressRecord.vectorizedObservationDimension ?? 0),
                "vectorized.actionDimension": Double(progressRecord.vectorizedActionDimension ?? 0)
            ],
            failureReasons: progressRecord.failureReasons ?? []
        )
        appendLearningCampaignLiveMetricSamples(summary)
    }

    private func shouldReplaceGenerationBest(
        generationIndex: Int,
        scalarFitness: Double
    ) -> Bool {
        guard scalarFitness.isFinite else { return false }
        let time = Double(generationIndex)
        guard let existing = learningCampaignLiveFitnessSamples.first(where: { $0.time == time }) else {
            return true
        }
        return scalarFitness >= existing.value
    }

    private func upsertMetricSample(_ sample: MetricSample, in samples: inout [MetricSample]) {
        guard sample.value.isFinite else { return }
        if let index = samples.firstIndex(where: { $0.time == sample.time }) {
            samples[index] = sample
        } else {
            samples.append(sample)
        }
        samples.sort { $0.time < $1.time }
        let maximumSampleCount = 500
        if samples.count > maximumSampleCount {
            samples.removeFirst(samples.count - maximumSampleCount)
        }
    }

    private func appendMetricSample(_ sample: MetricSample, to samples: inout [MetricSample]) {
        guard sample.value.isFinite else { return }
        if let index = samples.firstIndex(where: { $0.time == sample.time }) {
            samples[index] = sample
        } else {
            samples.append(sample)
        }
        let maximumSampleCount = 1_000
        if samples.count > maximumSampleCount {
            samples.removeFirst(samples.count - maximumSampleCount)
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

    private func learningCampaignTaskProfileID() -> String {
        switch taskMode {
        case .attitude, .lift:
            return "lift-v1"
        case .singleLift:
            return "singleLift-v1"
        }
    }

    private func applyLearningCampaignPreset(_ preset: LearningCampaignRunPreset) {
        let settings = learningCampaignPresetSettings(preset)
        learningCampaignSuites = settings.suites.map(String.init).joined(separator: ",")
        learningCampaignSeedCount = settings.seedCount
        learningCampaignPopulation = settings.population
        learningCampaignGenerations = settings.generations
        learningCampaignEliteCount = settings.eliteCount
        learningCampaignWorkers = settings.workers
        learningCampaignCandidateEvaluationConcurrency = settings.candidateEvaluationConcurrency
        learningCampaignEpisodes = settings.episodes
        learningCampaignMutationRate = settings.mutationRate
        learningCampaignMutationNoiseScale = settings.mutationNoiseScale
        learningCampaignAdaptiveMutation = settings.adaptiveMutationEnabled
        learningCampaignMinimumIncumbentImprovement = settings.minimumIncumbentImprovement
        learningCampaignCompactRetention = true
        learningCampaignLaunchEstimate = makeLearningCampaignLaunchEstimate(suites: settings.suites)
        learningCampaignReadiness = .idle
        emitUIAction(level: .info, message: "Learning campaign preset applied", action: "setLearningCampaignPreset", metadata: [
            "preset": preset.rawValue
        ])
    }

    private func learningCampaignPresetSettings(_ preset: LearningCampaignRunPreset) -> LearningCampaignPresetSettings {
        var settings: LearningCampaignPresetSettings
        switch preset {
        case .smoke:
            settings = LearningCampaignPresetSettings(
                suites: [6],
                seedCount: 1,
                population: 2,
                generations: 1,
                eliteCount: 1,
                workers: 1,
                candidateEvaluationConcurrency: 1,
                episodes: 1,
                mutationRate: 0.14,
                mutationNoiseScale: 0.025,
                adaptiveMutationEnabled: true,
                minimumIncumbentImprovement: 0
            )
        case .standard:
            settings = LearningCampaignPresetSettings(
                suites: [6],
                seedCount: 2,
                population: 100,
                generations: 1_000,
                eliteCount: 10,
                workers: 1,
                candidateEvaluationConcurrency: 100,
                episodes: 1,
                mutationRate: 0.14,
                mutationNoiseScale: 0.025,
                adaptiveMutationEnabled: true,
                minimumIncumbentImprovement: 0
            )
        case .convergence:
            settings = LearningCampaignPresetSettings(
                suites: [6],
                seedCount: 2,
                population: 100,
                generations: 1_000,
                eliteCount: 10,
                workers: 1,
                candidateEvaluationConcurrency: 100,
                episodes: 1,
                mutationRate: 0.16,
                mutationNoiseScale: 0.035,
                adaptiveMutationEnabled: true,
                minimumIncumbentImprovement: 0
            )
        case .full:
            settings = LearningCampaignPresetSettings(
                suites: [6, 7, 8],
                seedCount: 4,
                population: 100,
                generations: 2_000,
                eliteCount: 12,
                workers: 3,
                candidateEvaluationConcurrency: 100,
                episodes: 1,
                mutationRate: 0.14,
                mutationNoiseScale: 0.03,
                adaptiveMutationEnabled: true,
                minimumIncumbentImprovement: 0.01
            )
        }
        guard learningCampaignAutoParallelism else {
            return settings
        }
        let optimizedPopulation = learningCampaignMachineCapacity.recommendedPopulation(current: settings.population)
        let recommendation = learningCampaignMachineCapacity.recommendation(
            population: optimizedPopulation,
            suiteCount: settings.suites.count,
            episodes: settings.episodes
        )
        settings.population = optimizedPopulation
        settings.eliteCount = min(max(1, settings.eliteCount), optimizedPopulation)
        settings.workers = recommendation.workerCount
        settings.candidateEvaluationConcurrency = recommendation.candidateEvaluationConcurrency
        return settings
    }

    private func prepareStarterLearningProjectIfNeeded(forceNewArtifactRoot: Bool) throws -> LearningStarterProject {
        let sourcePath = learningCampaignSourceCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let artifactPath = learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let robotManifestPath = ensureRobotManifestForTask(reason: "starterProject")
        let sourceURL = URL(fileURLWithPath: sourcePath, isDirectory: true)
        let sourceIsComplete = !sourcePath.isEmpty
            && learningStarterProjectStore.checkpointIsComplete(
                at: sourceURL,
                policyContract: learningCampaignPolicyContract
            )
        let sourceIsValid = sourceIsComplete
            && starterSourceCheckpointIsValid(
                at: sourceURL,
                robotManifestPath: robotManifestPath,
                policyContract: learningCampaignPolicyContract,
                actionContract: learningCampaignActionContract
            )
        let artifactURL = URL(fileURLWithPath: artifactPath, isDirectory: true)
        let artifactIsReusable = !artifactPath.isEmpty
            ? try learningStarterProjectStore.artifactRootIsReusable(artifactURL)
            : false

        if sourceIsValid && !forceNewArtifactRoot && artifactIsReusable {
            isLearningStarterProjectReady = true
            learningStarterProjectStatus = "Ready"
            return LearningStarterProject(
                projectRoot: learningStarterProjectStore.projectRoot,
                sourceCheckpoint: URL(fileURLWithPath: sourcePath, isDirectory: true),
                artifactRoot: artifactURL
            )
        }

        if sourceIsValid && !forceNewArtifactRoot && !artifactIsReusable && !artifactPath.isEmpty {
            let nextArtifactURL = try makeSiblingRunArtifactRoot(after: artifactURL)
            learningCampaignArtifactDirectory = nextArtifactURL.path
            isLearningStarterProjectReady = true
            learningStarterProjectStatus = "Ready"
            return LearningStarterProject(
                projectRoot: nextArtifactURL.deletingLastPathComponent().deletingLastPathComponent(),
                sourceCheckpoint: URL(fileURLWithPath: sourcePath, isDirectory: true),
                artifactRoot: nextArtifactURL
            )
        }

        let observationTaskMode = taskMode
        let driveCount = starterDriveCount(for: observationTaskMode)
        let policyContract = learningCampaignPolicyContract
        let actionContract = learningCampaignActionContract

        if !sourcePath.isEmpty {
            try runnableProjectAssetPreparer.prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest(
                checkpointURL: sourceURL,
                displayName: learningCampaignExperimentName,
                robotManifestPath: robotManifestPath,
                embodiment: currentEmbodiment(),
                taskMode: observationTaskMode,
                driveCount: driveCount,
                expectedDriveCount: starterExpectedDriveCount(for: observationTaskMode),
                expectedObservationChannelCount: starterObservationChannelCount(for: observationTaskMode),
                auxEnabled: trainingUseAux,
                qualityGatingEnabled: trainingUseQualityGating,
                policyContract: policyContract,
                actionContract: actionContract
            ))
            try validateStarterSourceCheckpoint(
                at: sourceURL,
                robotManifestPath: robotManifestPath,
                policyContract: policyContract,
                actionContract: actionContract
            )
            let nextArtifactURL: URL
            if !forceNewArtifactRoot && artifactIsReusable && !artifactPath.isEmpty {
                nextArtifactURL = artifactURL
            } else if !artifactPath.isEmpty {
                nextArtifactURL = try makeSiblingRunArtifactRoot(after: artifactURL)
            } else {
                nextArtifactURL = try learningStarterProjectStore.makeNextRunArtifactRoot()
            }
            learningCampaignArtifactDirectory = nextArtifactURL.path
            isLearningStarterProjectReady = true
            learningStarterProjectStatus = "Ready"
            return LearningStarterProject(
                projectRoot: projectRootForSourceCheckpoint(sourceURL),
                sourceCheckpoint: sourceURL,
                artifactRoot: nextArtifactURL
            )
        }

        let project = try learningStarterProjectStore.prepareStarterProject(
            regenerateSourceCheckpoint: forceNewArtifactRoot || !sourceIsValid,
            policyContract: policyContract
        ) { [runnableProjectAssetPreparer, trainingUseAux, trainingUseQualityGating, observationTaskMode, driveCount, policyContract, actionContract] checkpointURL in
            try runnableProjectAssetPreparer.prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest(
                checkpointURL: checkpointURL,
                displayName: "Bounded Drone Autonomy Starter",
                robotManifestPath: robotManifestPath,
                embodiment: currentEmbodiment(),
                taskMode: observationTaskMode,
                driveCount: driveCount,
                expectedDriveCount: starterExpectedDriveCount(for: observationTaskMode),
                expectedObservationChannelCount: starterObservationChannelCount(for: observationTaskMode),
                auxEnabled: trainingUseAux,
                qualityGatingEnabled: trainingUseQualityGating,
                policyContract: policyContract,
                actionContract: actionContract
            ))
        }
        try validateStarterSourceCheckpoint(
            at: project.sourceCheckpoint,
            robotManifestPath: robotManifestPath,
            policyContract: learningCampaignPolicyContract,
            actionContract: learningCampaignActionContract
        )

        if forceNewArtifactRoot || !sourceIsValid {
            learningCampaignSourceCheckpointPath = project.sourceCheckpoint.path
        }
        if forceNewArtifactRoot || !artifactIsReusable {
            learningCampaignArtifactDirectory = project.artifactRoot.path
        }
        isLearningStarterProjectReady = true
        learningStarterProjectStatus = "Ready"
        return LearningStarterProject(
            projectRoot: project.projectRoot,
            sourceCheckpoint: URL(fileURLWithPath: learningCampaignSourceCheckpointPath, isDirectory: true),
            artifactRoot: URL(fileURLWithPath: learningCampaignArtifactDirectory, isDirectory: true)
        )
    }

    private func applyProjectTemplate(_ template: LearningProjectTemplate) {
        learningCampaignPolicyContract = template.policy
        learningCampaignActionContract = template.action
        let runtimeTask = template.primaryRunnableTrainingStage?.task ?? template.task
        switch runtimeTask {
        case "singleLift":
            taskMode = .singleLift
        case "lift":
            taskMode = .lift
        case "attitude":
            taskMode = .attitude
        default:
            break
        }
        learningStrategySelection = template.trainingStrategy.kind == .genetic ? .geneticLearning : .hybrid
    }

    private func makeProjectRunArtifactRoot(in projectRoot: URL) throws -> URL {
        let runsRoot = projectRoot.appendingPathComponent("runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runsRoot, withIntermediateDirectories: true)
        let stamp = max(0, Int(Date().timeIntervalSince1970))
        var candidate = runsRoot.appendingPathComponent("run-\(stamp)", isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = runsRoot.appendingPathComponent("run-\(stamp)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private func makeSiblingRunArtifactRoot(after artifactRoot: URL) throws -> URL {
        let runsRoot = artifactRoot.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: runsRoot, withIntermediateDirectories: true)
        let stamp = max(0, Int(Date().timeIntervalSince1970))
        var candidate = runsRoot.appendingPathComponent("run-\(stamp)", isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = runsRoot.appendingPathComponent("run-\(stamp)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private func latestProjectRunArtifactRoot(in projectRoot: URL) throws -> URL? {
        let runsRoot = projectRoot.appendingPathComponent("runs", isDirectory: true)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: runsRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        let runDirectories = try FileManager.default.contentsOfDirectory(
            at: runsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            var childIsDirectory = ObjCBool(false)
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &childIsDirectory)
                && childIsDirectory.boolValue
                && url.lastPathComponent.hasPrefix("run-")
        }
        guard !runDirectories.isEmpty else { return nil }
        return try runDirectories.max { lhs, rhs in
            let lhsDate = try contentModificationDate(lhs)
            let rhsDate = try contentModificationDate(rhs)
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }
    }

    private func contentModificationDate(_ url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return values.contentModificationDate ?? .distantPast
    }

    private func resumableLearningCampaignCheckpointURL() throws -> URL {
        let artifactURL = try currentLearningCampaignArtifactURL()
        return try commandSystem.learningCampaignContinuationSelection(from: artifactURL).checkpointURL
    }

    private func resumableLearningCampaignCheckpointURLIfAvailable() -> URL? {
        do {
            return try resumableLearningCampaignCheckpointURL()
        } catch {
            return nil
        }
    }

    private func currentLearningCampaignArtifactURL() throws -> URL {
        if let state = learningCampaignState {
            return state.artifactDirectory
        }
        let artifactPath = learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artifactPath.isEmpty else {
            throw LearningCampaignLaunchError.invalidConfiguration("Learning campaign artifact directory is empty.")
        }
        return URL(fileURLWithPath: artifactPath, isDirectory: true)
    }

    private func starterSourceCheckpointIsValid(
        at url: URL,
        robotManifestPath: String,
        policyContract: LearningProjectPolicyContract,
        actionContract: LearningProjectActionContract
    ) -> Bool {
        do {
            try validateStarterSourceCheckpoint(
                at: url,
                robotManifestPath: robotManifestPath,
                policyContract: policyContract,
                actionContract: actionContract
            )
            return true
        } catch {
            emitUIAction(level: .warning, message: "Starter source checkpoint validation failed", action: "validateStarterSourceCheckpoint", metadata: [
                "path": url.path,
                "error": "\(error)"
            ])
            return false
        }
    }

    private func projectRootForSourceCheckpoint(_ sourceURL: URL) -> URL {
        let parent = sourceURL.deletingLastPathComponent()
        if parent.lastPathComponent == "model-bundles" {
            return parent.deletingLastPathComponent()
        }
        return parent
    }

    private func validateStarterSourceCheckpoint(
        at url: URL,
        robotManifestPath: String,
        policyContract: LearningProjectPolicyContract,
        actionContract: LearningProjectActionContract
    ) throws {
        _ = try ManasMLXE2EPreflight().check(
            robotManifestPath: robotManifestPath,
            sourceCheckpointURL: url,
            requireSourceCheckpoint: true
        )
        if policyContract.actionEncoding == .ctbr {
            let manifestURL = url.appendingPathComponent("model.json", isDirectory: false)
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(ManasMLXTemporalCheckpointManifest.self, from: data)
            let expectedConfig = try ManasMLXTemporalPolicyContractResolver().makeConfig(
                from: policyContract,
                action: actionContract,
                hiddenSize: manifest.config.hiddenSize
            )
            guard manifest.config == expectedConfig else {
                throw LearningCampaignLaunchError.invalidConfiguration("starter checkpoint incompatible: ctbr policy config mismatch")
            }
            return
        }
        if let failure = try ManasMLXCheckpointCompatibility(
            expectedDriveCount: starterExpectedDriveCount(for: taskMode),
            expectedCoreInputSize: starterObservationChannelCount(for: taskMode) * 4
        ).validate(snapshotURL: url) {
            throw LearningCampaignLaunchError.invalidConfiguration("starter checkpoint incompatible: \(failure.description)")
        }
    }

    private func starterDriveCount(for taskMode: SimulationTaskMode) -> Int? {
        taskMode == .singleLift ? 1 : nil
    }

    private func starterExpectedDriveCount(for taskMode: SimulationTaskMode) -> Int {
        taskMode == .singleLift ? 1 : 4
    }

    private func starterObservationChannelCount(for taskMode: SimulationTaskMode) -> Int {
        switch taskMode {
        case .lift:
            return 64
        case .singleLift:
            return 8
        case .attitude:
            return 6
        }
    }

    private func invalidateLearningStarterProject(reason: String) {
        guard isLearningStarterProjectReady else { return }
        isLearningStarterProjectReady = false
        learningStarterProjectStatus = "Needs validation"
        learningCampaignReadiness = .idle
        emitUIAction(level: .info, message: "Starter learning project invalidated", action: "invalidateStarterLearningProject", metadata: [
            "reason": reason
        ])
    }

    private func makeTrainingRunRequest(
        runID: TrainingRunID,
        prepareMissingInputs: Bool
    ) throws -> TrainingRunRequest {
        guard learningStrategySelection.isExecutable else {
            throw LearningCampaignLaunchError.invalidConfiguration(
                "\(learningStrategySelection.title) is not executable. Select Hybrid to use the shared learning campaign runner."
            )
        }

        if prepareMissingInputs {
            _ = try prepareStarterLearningProjectIfNeeded(forceNewArtifactRoot: false)
        }

        let sourcePath = learningCampaignSourceCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let artifactPath = learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourcePath.isEmpty, !artifactPath.isEmpty else {
            throw LearningCampaignLaunchError.invalidConfiguration("Source checkpoint and artifact directory are required.")
        }

        let suites = try learningCampaignSuiteValues()
        let optimizedPopulation: Int
        let optimizedEliteCount: Int
        let optimizedWorkers: Int
        let optimizedCandidateConcurrency: Int
        if learningCampaignAutoParallelism {
            optimizedPopulation = learningCampaignMachineCapacity.recommendedPopulation(current: learningCampaignPopulation)
            let recommendation = learningCampaignMachineCapacity.recommendation(
                population: optimizedPopulation,
                suiteCount: suites.count,
                episodes: learningCampaignEpisodes
            )
            optimizedEliteCount = min(max(1, learningCampaignEliteCount), optimizedPopulation)
            optimizedWorkers = recommendation.workerCount
            optimizedCandidateConcurrency = recommendation.candidateEvaluationConcurrency
        } else {
            optimizedPopulation = learningCampaignPopulation
            optimizedEliteCount = learningCampaignEliteCount
            optimizedWorkers = learningCampaignWorkers
            optimizedCandidateConcurrency = learningCampaignCandidateEvaluationConcurrency
        }

        let configuration = TrainingRunConfiguration(
            trainingStageID: learningCampaignTrainingStageID,
            trainingStageDisplayName: learningCampaignTrainingStageDisplayName,
            trainingStageKind: learningCampaignTrainingStageKind,
            scenarioSelection: TrainingScenarioSelection(
                suiteIDs: suites,
                episodesPerSuite: learningCampaignEpisodes,
                tier: TrainingDeterminismTier(uiTier: learningCampaignTier()),
                cutPeriodSteps: cutPeriodSteps
            ),
            resources: TrainingResourcePlan(
                workerCount: optimizedWorkers,
                candidateEvaluationConcurrency: optimizedCandidateConcurrency
            ),
            evolution: TrainingEvolutionSettings(
                eliteCount: optimizedEliteCount,
                searchStrategy: .qualityDiversity,
                variation: .gaussian,
                mutation: TrainingMutationSchedule(
                    rate: learningCampaignMutationRate,
                    noiseScale: learningCampaignMutationNoiseScale,
                    adaptiveEnabled: learningCampaignAdaptiveMutation
                ),
                minimumIncumbentImprovement: learningCampaignMinimumIncumbentImprovement
            ),
            control: TrainingControlSettings(
                robotManifestPath: ensureRobotManifestForTask(reason: "learningCampaignConfig"),
                kp: kp,
                kd: kd,
                yawDamping: yawDamping,
                hoverScale: hoverThrustScale
            ),
            artifacts: TrainingArtifactPolicy(
                retention: learningCampaignCompactRetention ? .compact : .full,
                requiresInitialParentPass: learningCampaignRequiresInitialParentPass
            ),
            autonomyDomain: learningCampaignAutonomyDomain
        )
        return TrainingRunRequest(
            runID: runID,
            projectRoot: learningStarterProjectStore.projectRoot,
            artifactRoot: URL(fileURLWithPath: artifactPath, isDirectory: true),
            taskProfileID: learningCampaignTaskProfileID(),
            policyContract: learningCampaignPolicyContract,
            actionContract: learningCampaignActionContract,
            sourceBundle: ModelBundleReference(
                bundleID: URL(fileURLWithPath: sourcePath, isDirectory: true).lastPathComponent,
                kind: .source,
                url: URL(fileURLWithPath: sourcePath, isDirectory: true)
            ),
            seedCount: learningCampaignSeedCount,
            populationSize: optimizedPopulation,
            generationLimit: learningCampaignGenerations,
            configuration: configuration
        )
    }

    private func makeLearningCampaignLaunchEstimate(suites: [Int]) -> LearningCampaignLaunchEstimate {
        let estimatedPopulation = learningCampaignAutoParallelism
            ? learningCampaignMachineCapacity.recommendedPopulation(current: learningCampaignPopulation)
            : learningCampaignPopulation
        let recommendation = learningCampaignMachineCapacity.recommendation(
            population: estimatedPopulation,
            suiteCount: suites.count,
            episodes: learningCampaignEpisodes
        )
        let workerCount = learningCampaignAutoParallelism ? recommendation.workerCount : learningCampaignWorkers
        let candidateConcurrency = learningCampaignAutoParallelism
            ? recommendation.candidateEvaluationConcurrency
            : learningCampaignCandidateEvaluationConcurrency
        let totalParallelSlots = workerCount * candidateConcurrency
        let capacitySlots = learningCampaignAutoParallelism
            ? learningCampaignMachineCapacity.acceleratedParallelSlotBudget
            : learningCampaignMachineCapacity.usableProcessorSlots
        let utilization = min(
            1,
            Double(totalParallelSlots) / Double(capacitySlots)
        )
        let candidateEvaluations = max(1, learningCampaignSeedCount)
            * max(1, estimatedPopulation)
            * max(1, learningCampaignGenerations)
        let regressionRollouts = candidateEvaluations * max(1, suites.count)
        let regressionEpisodes = regressionRollouts * max(1, learningCampaignEpisodes)
        return LearningCampaignLaunchEstimate(
            candidateEvaluations: candidateEvaluations,
            regressionRollouts: regressionRollouts,
            regressionEpisodes: regressionEpisodes,
            workerCount: workerCount,
            candidateConcurrency: candidateConcurrency,
            machineSummary: learningCampaignMachineCapacity.summary,
            usableProcessorSlots: capacitySlots,
            totalParallelSlots: totalParallelSlots,
            utilizationLabel: "\(Int((utilization * 100).rounded()))%",
            retention: learningCampaignCompactRetention ? "compact" : "full",
            estimatedAt: Date()
        )
    }

    private func applyLearningCampaignParallelismRecommendation(suites: [Int]) {
        let optimizedPopulation = learningCampaignMachineCapacity.recommendedPopulation(
            current: learningCampaignPopulation
        )
        learningCampaignPopulation = optimizedPopulation
        learningCampaignEliteCount = min(max(learningCampaignEliteCount, min(2, optimizedPopulation)), optimizedPopulation)
        let recommendation = learningCampaignMachineCapacity.recommendation(
            population: optimizedPopulation,
            suiteCount: suites.count,
            episodes: learningCampaignEpisodes
        )
        learningCampaignWorkers = recommendation.workerCount
        learningCampaignCandidateEvaluationConcurrency = recommendation.candidateEvaluationConcurrency
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
                throw LearningCampaignLaunchError.invalidConfiguration("Invalid suite: \(token)")
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

    /// Removes a single run, keeping the rest. Selection falls back to the newest
    /// remaining run when the deleted run was selected.
    func deleteRun(id: UUID) {
        runs.removeAll { $0.id == id }
        if selectedRunID == id {
            selectedRunID = runs.first?.id
            selectedScenarioKey = nil
        }
    }

    func insertRun(_ run: RunRecord) {
        runs.insert(run, at: 0)
        selectedRunID = run.id
        selectedScenarioKey = run.scenarios.first?.id
    }

    func setRobotManifestPath(_ path: String, source: String, emitLog: Bool = true) {
        robotManifestPath = path
        robotCachePath = nil
        robotCache = nil
        robotCacheError = nil
        refreshManualActuatorLayout()
        invalidateLearningStarterProject(reason: "robotManifestChanged")
        guard emitLog else { return }
        emitUIAction(level: .info, message: "Robot manifest set", action: "setRobotManifestPath", metadata: [
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

    private func resolvedRobotManifestPathForCache() -> String {
        KuyuUIModelPaths.resolveRobotManifestPath(robotManifestPath)
    }

    private func resolvedRobotManifestPath() -> String {
        let resolved = resolvedRobotManifestPathForCache()
        if resolved != robotManifestPath {
            let previous = robotManifestPath
            robotManifestPath = resolved
            emitUIAction(level: .info, message: "Robot manifest path resolved", action: "robotManifestPathResolved", metadata: [
                "from": previous,
                "to": resolved,
                "reason": "defaultPath"
            ])
        }
        return resolved
    }

    private func robotSnapshot() -> LoadedKuyuRobot? {
        let resolved = resolvedRobotManifestPathForCache().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolved.isEmpty else {
            robotCachePath = nil
            robotCache = nil
            robotCacheError = nil
            return nil
        }

        if robotCachePath == resolved {
            return robotCache
        }

        robotCachePath = resolved
        do {
            let loader = KuyuModelLoader()
            let loaded = try loader.loadRobot(path: resolved)
            robotCache = loaded
            robotCacheError = nil
            refreshManualActuatorLayout()
            return loaded
        } catch {
            robotCache = nil
            robotCacheError = "\(error)"
            refreshManualActuatorLayout()
            return nil
        }
    }

    private func trainingObservationMetadata() -> TrainingObservationMetadata? {
        guard let observation = robotSnapshot()?.embodiment.observation else { return nil }
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
        if let embodiment = robotCache?.embodiment {
            let count = embodiment.signals.actuator.count
            if currentRobotIsArticulatedDynamic(), count > 0 {
                return count
            }
            if count == defaultCount {
                return count
            }
        }
        return defaultCount
    }

    private func currentMotorNerveProfile() -> String {
        let fallback = currentRobotIsArticulatedDynamic()
            ? "articulated-dynamic"
            : (taskMode == .singleLift ? "fixed-single-prop" : "fixed-quad")
        guard let embodiment = robotSnapshot()?.embodiment else { return fallback }
        let expectedDriveCount = currentRobotIsArticulatedDynamic()
            ? embodiment.signals.actuator.count
            : (taskMode == .singleLift ? 1 : 4)
        if embodiment.control.driveChannels.count != expectedDriveCount {
            return fallback
        }
        if embodiment.motorNerve.stages.contains(where: { $0.type == .custom }) {
            return fallback
        }
        return "embodiment-contract"
    }

    private func preflightParameters(modelPath: String) throws -> ReferenceQuadrotorParameters? {
        let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        do {
            let loader = KuyuModelLoader()
            let loaded = try loader.loadRobot(path: trimmed)
            let inertial = try loader.loadPlantInertialProperties(robot: loaded)
            let parameters = try ReferenceQuadrotorParameters.reference(
                from: inertial,
                robotID: loaded.manifest.robotID
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
        try preflightParameters(modelPath: resolvedRobotManifestPath())
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
            // An unreadable root is reported, not treated as a silent "absent":
            // the caller switches the training route based on this answer.
            emitTerminal(level: .warning, message: "Training dataset probe failed; treating dataset as absent", metadata: [
                "path": root.path,
                "error": "\(error)"
            ])
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
            let telemetry: WorldStepTelemetry = { [weak self] step in
                Task { @MainActor in
                    self?.recordLiveStep(step)
                }
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
        metadata["robotManifest"] = resolvedRobotManifestPathForCache()

        let profileMeta = taskProfileMetadata()
        for (key, value) in profileMeta {
            metadata[key] = value
        }

        if let loaded = robotSnapshot() {
            metadata["robotID"] = loaded.manifest.robotID
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
        guard let loaded = robotSnapshot() else { return nil }
        let loader = KuyuModelLoader()
        if let asset = loader.primaryRenderAsset(robot: loaded) {
            let url = loader.resolveRenderAsset(asset, baseURL: loaded.baseURL)
            return RenderAssetInfo(
                name: asset.name,
                url: url,
                format: asset.format,
                scale: asset.scale
            )
        }

        return nil
    }

    func currentEmbodiment() -> EmbodimentContract? {
        robotSnapshot()?.embodiment
    }

    func currentRobotManifest() -> KuyuRobotManifest? {
        robotSnapshot()?.manifest
    }

    func currentRobotLoadError() -> String? {
        _ = robotSnapshot()
        return robotCacheError
    }

    func motorNerveStages() -> [MotorNerveStageDefinition] {
        robotSnapshot()?.embodiment.motorNerve.stages ?? []
    }

    func driveSignalDefinitions() -> [SignalDefinition] {
        guard let embodiment = robotSnapshot()?.embodiment else { return [] }
        return orderedSignals(ids: embodiment.control.driveChannels, from: embodiment.signals.drive)
    }

    func reflexSignalDefinitions() -> [SignalDefinition] {
        guard let embodiment = robotSnapshot()?.embodiment else { return [] }
        return orderedSignals(ids: embodiment.control.reflexChannels, from: embodiment.signals.reflex)
    }

    func embodimentDescendingChannelIDs() -> [String] {
        guard let embodiment = robotSnapshot()?.embodiment else { return [] }
        return embodiment.control.descendingChannels ?? []
    }

    func descendingSignalDefinitions() -> [SignalDefinition] {
        guard let embodiment = robotSnapshot()?.embodiment else { return [] }
        let definitions = embodiment.signals.descending ?? []
        guard let descendingChannels = embodiment.control.descendingChannels,
              !descendingChannels.isEmpty else {
            return definitions.sorted { $0.index < $1.index }
        }
        return orderedSignals(ids: descendingChannels, from: definitions)
    }

    func actuatorSignalDefinitions() -> [SignalDefinition] {
        let definitions = robotSnapshot()?.embodiment.signals.actuator ?? []
        return definitions.sorted { $0.index < $1.index }
    }

    func motorNerveSignalDefinitions() -> [SignalDefinition] {
        robotSnapshot()?.embodiment.signals.motorNerve ?? []
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

        guard let embodiment = robotCache?.embodiment else {
            return ranges
        }

        let sortedSignals = embodiment.signals.actuator.sorted { $0.index < $1.index }
        var limitsBySignalID: [String: ClosedRange<Double>] = [:]
        for actuator in embodiment.actuators {
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
            channelIDs: embodimentDescendingChannelIDs(),
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
        from definitions: [SignalDefinition]
    ) -> [SignalDefinition] {
        let map = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        return ids.compactMap { map[$0] }
    }

}

private extension TrainingDeterminismTier {
    init(uiTier: LearningCampaignTier) {
        switch uiTier {
        case .tier0:
            self = .tier0
        case .tier1:
            self = .tier1
        case .tier2:
            self = .tier2
        }
    }
}

private struct LearningCampaignPresetSettings {
    let suites: [Int]
    let seedCount: Int
    var population: Int
    let generations: Int
    var eliteCount: Int
    var workers: Int
    var candidateEvaluationConcurrency: Int
    let episodes: Int
    let mutationRate: Double
    let mutationNoiseScale: Double
    let adaptiveMutationEnabled: Bool
    let minimumIncumbentImprovement: Double
}
