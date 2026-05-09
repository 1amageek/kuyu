import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

public struct KuyuRegressionRunConfig: Sendable, Equatable {
    public let controller: ControllerSelection
    public let snapshotURL: URL?
    public let tier: LearningCampaignTier
    public let cutPeriodSteps: UInt64
    public let task: LearningCampaignRolloutTask
    public let suites: [Int]
    public let episodes: Int
    public let workers: Int
    public let maxSteps: Int?
    public let maxWallTime: Double?
    public let modelDescriptorPath: String
    public let artifactRoot: URL
    public let kp: Double
    public let kd: Double
    public let yawDamping: Double
    public let hoverScale: Double
    public let failOnTruncation: Bool
    public let minimumRewardAverage: Double?
    public let useQualityGating: Bool
    public let checksEnvironmentReadiness: Bool

    public init(
        controller: ControllerSelection,
        snapshotURL: URL?,
        tier: LearningCampaignTier,
        cutPeriodSteps: UInt64,
        task: LearningCampaignRolloutTask,
        suites: [Int],
        episodes: Int,
        workers: Int,
        maxSteps: Int? = nil,
        maxWallTime: Double? = nil,
        modelDescriptorPath: String,
        artifactRoot: URL,
        kp: Double,
        kd: Double,
        yawDamping: Double,
        hoverScale: Double,
        failOnTruncation: Bool,
        minimumRewardAverage: Double?,
        useQualityGating: Bool,
        checksEnvironmentReadiness: Bool = true
    ) {
        self.controller = controller
        self.snapshotURL = snapshotURL
        self.tier = tier
        self.cutPeriodSteps = cutPeriodSteps
        self.task = task
        self.suites = suites
        self.episodes = episodes
        self.workers = workers
        self.maxSteps = maxSteps
        self.maxWallTime = maxWallTime
        self.modelDescriptorPath = modelDescriptorPath
        self.artifactRoot = artifactRoot
        self.kp = kp
        self.kd = kd
        self.yawDamping = yawDamping
        self.hoverScale = hoverScale
        self.failOnTruncation = failOnTruncation
        self.minimumRewardAverage = minimumRewardAverage
        self.useQualityGating = useQualityGating
        self.checksEnvironmentReadiness = checksEnvironmentReadiness
    }
}

public enum KuyuRegressionRunnerError: Error, Sendable, Equatable {
    case invalidSuites
    case invalidEpisodes
    case missingSnapshot
    case invalidHoverScale
}

public struct KuyuRegressionRunner: Sendable {
    public init() {}

    public func run(config: KuyuRegressionRunConfig) async throws -> KuyuRegressionSummary {
        try FileManager.default.createDirectory(at: config.artifactRoot, withIntermediateDirectories: true)
        if config.controller == .manasMLX, config.snapshotURL == nil {
            throw KuyuRegressionRunnerError.missingSnapshot
        }
        guard config.episodes > 0 else {
            throw KuyuRegressionRunnerError.invalidEpisodes
        }

        let environmentController: ControllerSelection = config.controller.isBaselineController
            ? config.controller
            : .teacherBaseline
        let regressionProfile = try TaskEvaluationProfile.profile(task: config.task.rawValue)
        let effectiveMinimumRewardAverage = KuyuRegressionQualityGatePolicy.minimumRewardAverage(
            override: config.minimumRewardAverage,
            task: regressionProfile.task
        )

        if config.controller == .manasMLX {
            do {
                _ = try await ManasMLXE2EPreflight().check(
                    descriptorPath: config.modelDescriptorPath,
                    sourceCheckpointURL: config.snapshotURL,
                    requireSourceCheckpoint: true
                )
            } catch {
                let gateReport = KuyuRegressionGatePolicy.report(
                    preflightFailure: String(describing: error),
                    environmentTasks: [],
                    rolloutSuites: [],
                    failOnTruncation: config.failOnTruncation,
                    minimumRewardAverage: effectiveMinimumRewardAverage,
                    qualityGateTask: regressionProfile.task
                )
                let summary = KuyuRegressionSummary(
                    artifactRoot: config.artifactRoot.path,
                    startedAt: Date(),
                    controller: config.controller.rawValue,
                    environmentController: environmentController.rawValue,
                    snapshot: config.snapshotURL?.path,
                    preflightPassed: false,
                    preflightFailure: String(describing: error),
                    environmentReady: false,
                    environmentTasks: [],
                    rolloutPassed: false,
                    rolloutSuites: [],
                    gateReport: gateReport,
                    allPassed: gateReport.accepted
                )
                try write(summary: summary, to: config.artifactRoot)
                return summary
            }
        }

        let determinism = try config.tier.makeDeterminism()
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: config.cutPeriodSteps)
        let loadedDescriptor = try loadLoadedDescriptor(modelPath: config.modelDescriptorPath)
        let descriptor = loadedDescriptor?.descriptor
        let parameters = try makeRolloutParameters(
            task: config.task,
            loadedDescriptor: loadedDescriptor,
            hoverThrustScale: config.hoverScale
        )
        let gains = try ImuRateDampingCutGains(
            kp: config.kp,
            kd: config.kd,
            yawDamping: config.yawDamping,
            hoverThrustScale: config.hoverScale
        )

        let environmentReport: KuyuEnvironmentReadinessReport
        if config.checksEnvironmentReadiness {
            environmentReport = try await KuyuEnvironmentReadinessChecker().check(
                tasks: [simulationTaskMode(from: config.task)],
                controller: environmentController,
                parameters: parameters,
                schedule: schedule,
                determinism: determinism,
                gains: gains,
                modelDescriptorPath: config.modelDescriptorPath,
                descriptor: descriptor,
                artifactRoot: config.artifactRoot.appendingPathComponent("environment-readiness", isDirectory: true)
            )
        } else {
            environmentReport = KuyuEnvironmentReadinessReport(tasks: [])
        }

        if config.controller == .manasMLX,
           let snapshotURL = config.snapshotURL,
           let compatibilityFailure = try regressionSnapshotCompatibilityFailure(
            snapshotURL: snapshotURL,
            task: config.task
           ) {
            let rolloutEntries = config.suites.map { suite in
                KuyuRegressionRolloutEntry(
                    suite: suite,
                    track: regressionTrackName(for: suite),
                    policyID: "manasMLX-regression",
                    episodeCount: 0,
                    rewardSum: 0,
                    rewardAverage: 0,
                    doneCount: 0,
                    truncatedCount: 0,
                    failureCount: 1,
                    cancelledCount: 0,
                    failureReasons: [compatibilityFailure],
                    taskPassCount: 0,
                    taskFailureCount: 1,
                    taskFailureReasons: [compatibilityFailure],
                    taskQuality: [],
                    workerSummaries: [],
                    artifactPath: nil
                )
            }
            let gateReport = KuyuRegressionGatePolicy.report(
                preflightFailure: nil,
                environmentTasks: environmentReport.tasks,
                rolloutSuites: rolloutEntries,
                failOnTruncation: config.failOnTruncation,
                minimumRewardAverage: effectiveMinimumRewardAverage,
                qualityGateTask: regressionProfile.task
            )
            let summary = KuyuRegressionSummary(
                artifactRoot: config.artifactRoot.path,
                startedAt: Date(),
                controller: config.controller.rawValue,
                environmentController: environmentController.rawValue,
                snapshot: config.snapshotURL?.path,
                preflightPassed: true,
                preflightFailure: nil,
                environmentReady: environmentReport.allReady,
                environmentTasks: environmentReport.tasks,
                rolloutPassed: false,
                rolloutSuites: rolloutEntries,
                gateReport: gateReport,
                allPassed: gateReport.accepted
            )
            try write(summary: summary, to: config.artifactRoot)
            return summary
        }

        var rolloutEntries: [KuyuRegressionRolloutEntry] = []
        for suite in config.suites {
            let definitions = try makeRegressionRolloutDefinitions(
                task: config.task,
                suite: suite,
                episodes: config.episodes
            )
            let track = regressionTrackName(for: suite)
            let motorSettings = regressionProfile.motorNerveSettings(controllerRawValue: config.controller.rawValue)
            let runner = RolloutRunner(
                parameters: parameters,
                schedule: schedule,
                determinism: determinism,
                hoverThrustScale: config.hoverScale,
                loadedDescriptor: loadedDescriptor,
                motorNerveRateLimitPerSecond: motorSettings.rateLimitPerSecond,
                motorNerveSmoothingTimeConstant: motorSettings.smoothingTimeConstant,
                limits: try RolloutRunner.Limits.validated(
                    maxStepsPerEpisode: config.maxSteps,
                    maxWallTimeSeconds: config.maxWallTime
                )
            )
            let policyFactory = try makePolicyFactory(
                controller: config.controller,
                snapshotURL: config.snapshotURL,
                parameters: parameters,
                gains: gains,
                useQualityGating: config.useQualityGating
            )
            do {
                let episodesOut: [RolloutEpisode]
                if config.workers == 1 {
                    episodesOut = try await runner.run(definitions: definitions, policyFactory: policyFactory)
                } else {
                    let collector = try ParallelRolloutCollector(runner: runner, workerCount: config.workers)
                    episodesOut = try await collector.collect(definitions: definitions, policyFactory: policyFactory)
                }
                let rolloutSummary = RolloutSummary(episodes: episodesOut)
                let rewardAverage = rolloutSummary.episodeCount > 0
                    ? rolloutSummary.rewardSum / Double(rolloutSummary.episodeCount)
                    : 0
                let taskEvaluation = evaluateEpisodes(
                    definitions: definitions,
                    episodes: episodesOut,
                    determinism: determinism
                )
                rolloutEntries.append(KuyuRegressionRolloutEntry(
                    suite: suite,
                    track: track,
                    policyID: policyFactory.policyID,
                    episodeCount: rolloutSummary.episodeCount,
                    rewardSum: rolloutSummary.rewardSum,
                    rewardAverage: rewardAverage,
                    doneCount: rolloutSummary.doneCount,
                    truncatedCount: rolloutSummary.truncatedCount,
                    failureCount: rolloutSummary.failureCount,
                    cancelledCount: rolloutSummary.cancelledCount,
                    failureReasons: Array(Set(episodesOut.compactMap(\.failureReason))).sorted(),
                    taskPassCount: taskEvaluation.passCount,
                    taskFailureCount: taskEvaluation.failureCount,
                    taskFailureReasons: taskEvaluation.failureReasons,
                    taskQuality: taskEvaluation.taskQuality,
                    workerSummaries: workerSummaries(
                        episodes: episodesOut,
                        snapshotURL: config.snapshotURL,
                        rolloutRoot: config.artifactRoot.appendingPathComponent("rollouts/\(track)", isDirectory: true)
                    ),
                    artifactPath: nil
                ))
            } catch {
                rolloutEntries.append(KuyuRegressionRolloutEntry(
                    suite: suite,
                    track: track,
                    policyID: policyFactory.policyID,
                    episodeCount: 0,
                    rewardSum: 0,
                    rewardAverage: 0,
                    doneCount: 0,
                    truncatedCount: 0,
                    failureCount: 1,
                    cancelledCount: 0,
                    failureReasons: [String(describing: error)],
                    taskPassCount: 0,
                    taskFailureCount: 1,
                    taskFailureReasons: [String(describing: error)],
                    taskQuality: [],
                    workerSummaries: [],
                    artifactPath: nil
                ))
            }
        }

        let rolloutPassed = rolloutEntries.allSatisfy { entry in
            entry.failureCount == 0
                && entry.cancelledCount == 0
                && entry.taskFailureCount == 0
                && entry.taskPassCount == entry.episodeCount
                && (!config.failOnTruncation || entry.truncatedCount == 0)
        }
        let gateReport = KuyuRegressionGatePolicy.report(
            preflightFailure: nil,
            environmentTasks: environmentReport.tasks,
            rolloutSuites: rolloutEntries,
            failOnTruncation: config.failOnTruncation,
            minimumRewardAverage: effectiveMinimumRewardAverage,
            qualityGateTask: regressionProfile.task
        )
        let summary = KuyuRegressionSummary(
            artifactRoot: config.artifactRoot.path,
            startedAt: Date(),
            controller: config.controller.rawValue,
            environmentController: environmentController.rawValue,
            snapshot: config.snapshotURL?.path,
            preflightPassed: true,
            preflightFailure: nil,
            environmentReady: environmentReport.allReady,
            environmentTasks: environmentReport.tasks,
            rolloutPassed: rolloutPassed,
            rolloutSuites: rolloutEntries,
            gateReport: gateReport,
            allPassed: gateReport.accepted
        )
        try write(summary: summary, to: config.artifactRoot)
        return summary
    }

    private func write(summary: KuyuRegressionSummary, to artifactRoot: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(summary).write(
            to: artifactRoot.appendingPathComponent("kuyu-regression-summary.json"),
            options: [.atomic]
        )
        _ = try KuyuRegressionArtifactValidator().loadAndValidate(from: artifactRoot)
    }
}

private struct RegressionTaskEvaluation {
    let passCount: Int
    let failureCount: Int
    let failureReasons: [String]
    let taskQuality: [ReferenceQuadrotorTaskQualitySummary]
}

private func evaluateEpisodes(
    definitions: [ReferenceQuadrotorScenarioDefinition],
    episodes: [RolloutEpisode],
    determinism: DeterminismConfig
) -> RegressionTaskEvaluation {
    let definitionByKey = Dictionary(
        uniqueKeysWithValues: definitions.map {
            (rolloutDefinitionKey(scenarioID: $0.config.id.rawValue, seed: $0.config.seed.rawValue), $0)
        }
    )
    let evaluator = ReferenceQuadrotorScenarioEvaluator()
    let qualityEvaluator = ReferenceQuadrotorTaskQualityEvaluator()
    var passCount = 0
    var failureReasons: [String] = []
    var taskQuality: [ReferenceQuadrotorTaskQualitySummary] = []

    for episode in episodes {
        guard let definition = definitionByKey[rolloutDefinitionKey(scenarioID: episode.scenarioId, seed: episode.seed)] else {
            failureReasons.append("missing-definition")
            continue
        }
        let failureReason = episode.failureReason.flatMap(FailureReason.init(rawValue:))
        let log = SimulationLog(
            scenarioId: definition.config.id,
            seed: definition.config.seed,
            timeStep: definition.config.timeStep,
            determinism: determinism,
            configHash: episode.configHash,
            events: episode.steps.map(\.log),
            failureReason: failureReason,
            failureTime: episode.failureTime
        )
        let evaluation = evaluator.evaluate(definition: definition, log: log)
        let quality = qualityEvaluator.evaluate(definition: definition, log: log)
        taskQuality.append(quality)
        if evaluation.passed {
            passCount += 1
        } else {
            failureReasons.append(contentsOf: evaluation.failures.map { "task:\($0)" })
        }
    }
    return RegressionTaskEvaluation(
        passCount: passCount,
        failureCount: episodes.count - passCount,
        failureReasons: Array(Set(failureReasons)).sorted(),
        taskQuality: taskQuality
    )
}

private func makePolicyFactory(
    controller: ControllerSelection,
    snapshotURL: URL?,
    parameters: ReferenceQuadrotorParameters,
    gains: ImuRateDampingCutGains,
    useQualityGating: Bool
) throws -> any ReferenceQuadrotorPolicyFactory {
    switch controller {
    case .baseline, .teacherBaseline:
        return KuyAtt1BaselinePolicyFactory(parameters: parameters, gains: gains, mode: .teacher)
    case .sensorBaseline:
        return KuyAtt1BaselinePolicyFactory(parameters: parameters, gains: gains, mode: .sensor)
    case .manasMLX:
        guard let snapshotURL else {
            throw KuyuRegressionRunnerError.missingSnapshot
        }
        return ManasMLXRolloutPolicyFactory(
            snapshotDirectory: snapshotURL,
            policyID: "manasMLX-regression",
            useQualityGating: useQualityGating
        )
    }
}

private func makeRegressionRolloutDefinitions(
    task: LearningCampaignRolloutTask,
    suite: Int,
    episodes: Int
) throws -> [ReferenceQuadrotorScenarioDefinition] {
    guard episodes > 0 else {
        throw KuyuRegressionRunnerError.invalidEpisodes
    }
    if task == .lift || task == .singleLift {
        return try makeLiftSuiteDefinitions(task: task, suite: suite, episodes: episodes)
    }
    let track: LongHorizonBenchmarkTrack
    switch suite {
    case 6:
        track = .longHorizonTask
    case 7:
        track = .morphologyTransfer
    case 8:
        track = .disturbanceDelayPartialObservability
    default:
        throw KuyuRegressionRunnerError.invalidSuites
    }
    let benchmark = try LongHorizonBenchmarkSuite.makeDefault(
        scenariosPerTrack: max(episodes, 1),
        baseSeed: 60_000
    )
    return benchmark.cases.filter { $0.track == track }.map(\.definition)
}

private func makeLiftSuiteDefinitions(
    task: LearningCampaignRolloutTask,
    suite: Int,
    episodes: Int
) throws -> [ReferenceQuadrotorScenarioDefinition] {
    let baseDefinitions: [ReferenceQuadrotorScenarioDefinition] = switch task {
    case .attitude:
        try KuyAtt1Suite().scenarios()
    case .lift:
        try KuyLiftSuite().scenarios()
    case .singleLift:
        try KuySingleLiftSuite().scenarios()
    }
    return try (0..<episodes).map { index in
        try liftRegressionDefinition(
            task: task,
            suite: suite,
            index: index,
            definition: baseDefinitions[index % baseDefinitions.count]
        )
    }
}

private func liftRegressionDefinition(
    task: LearningCampaignRolloutTask,
    suite: Int,
    index: Int,
    definition: ReferenceQuadrotorScenarioDefinition
) throws -> ReferenceQuadrotorScenarioDefinition {
    guard let liftEnvelope = definition.liftEnvelope else {
        return definition
    }
    let targetOffset: Double
    let initialOffset: Double
    let actuatorDegradation: ActuatorDegradation?
    let torqueEvents: [TorqueDisturbanceEvent]
    let hfEvents: [HFStressEvent]
    switch suite {
    case 6:
        targetOffset = 0
        initialOffset = 0
        actuatorDegradation = definition.actuatorDegradation
        torqueEvents = definition.torqueEvents
        hfEvents = definition.hfEvents
    case 7:
        targetOffset = task == .singleLift ? 0.02 : 0.05
        initialOffset = 0
        actuatorDegradation = definition.actuatorDegradation
        torqueEvents = definition.torqueEvents
        hfEvents = definition.hfEvents
    case 8:
        targetOffset = task == .singleLift ? -0.01 : -0.02
        initialOffset = 0
        actuatorDegradation = definition.actuatorDegradation
        torqueEvents = definition.torqueEvents + [
            try TorqueDisturbanceEvent(
                startTime: max(0.75, definition.config.duration * 0.35),
                duration: 0.05,
                torqueBody: Axis3(x: task == .singleLift ? 0.0002 : 0.0005, y: 0, z: 0)
            ),
        ]
        hfEvents = definition.hfEvents + [
            try HFStressEvent(
                kind: .latencySpike,
                startTime: max(1.0, definition.config.duration * 0.50),
                duration: 0.01,
                magnitude: 0.01
            ),
        ]
    default:
        throw KuyuRegressionRunnerError.invalidSuites
    }
    let targetZ = max(0.05, liftEnvelope.targetZ + targetOffset)
    let adjustedLiftEnvelope = LiftEnvelope(
        targetZ: targetZ,
        tolerance: liftEnvelope.tolerance,
        maxVelocity: liftEnvelope.maxVelocity,
        warmupTime: liftEnvelope.warmupTime,
        requiredHoldTime: liftEnvelope.requiredHoldTime
    )
    let prefix: String = switch task {
    case .attitude:
        "KUY-ATT-M2-S\(suite)"
    case .lift:
        "KUY-LIFT-M2-S\(suite)"
    case .singleLift:
        "KUY-SLIFT-M2-S\(suite)"
    }
    return ReferenceQuadrotorScenarioDefinition(
        config: try ScenarioConfig(
            id: try ScenarioID("\(prefix)/SCN-\(index + 1)"),
            seed: ScenarioSeed(definition.config.seed.rawValue &+ UInt64(suite * 10_000 + index)),
            duration: definition.config.duration,
            timeStep: definition.config.timeStep
        ),
        kind: definition.kind,
        initialPosition: Axis3(
            x: definition.initialPosition.x,
            y: definition.initialPosition.y,
            z: max(0.05, targetZ + initialOffset)
        ),
        initialAttitude: definition.initialAttitude,
        initialAngularVelocity: definition.initialAngularVelocity,
        safetyEnvelope: definition.safetyEnvelope,
        liftEnvelope: adjustedLiftEnvelope,
        torqueEvents: torqueEvents,
        actuatorDegradation: actuatorDegradation,
        gyroDriftScale: suite == 8 ? max(definition.gyroDriftScale, 1.5) : definition.gyroDriftScale,
        swapEvents: definition.swapEvents,
        hfEvents: hfEvents
    )
}

private func loadLoadedDescriptor(modelPath: String) throws -> LoadedRobotDescriptor? {
    let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return try RobotDescriptorLoader().loadDescriptor(path: trimmed)
}

private func makeRolloutParameters(
    task: LearningCampaignRolloutTask,
    loadedDescriptor: LoadedRobotDescriptor?,
    hoverThrustScale: Double
) throws -> ReferenceQuadrotorParameters {
    guard hoverThrustScale.isFinite, hoverThrustScale > 0 else {
        throw KuyuRegressionRunnerError.invalidHoverScale
    }
    if let loadedDescriptor {
        let inertial = try RobotDescriptorLoader().loadPlantInertialProperties(descriptor: loadedDescriptor)
        let parameters = try ReferenceQuadrotorParameters.reference(
            from: inertial,
            robotID: loadedDescriptor.descriptor.robot.robotID
        )
        guard task == .singleLift else { return parameters }
        return try KuyuSingleLiftParameterTuning.tuned(parameters: parameters, hoverThrustScale: hoverThrustScale)
    }
    guard task == .singleLift else { return .baseline }
    return try KuyuSingleLiftParameterTuning.tuned(parameters: .baseline, hoverThrustScale: hoverThrustScale)
}

private func workerSummaries(
    episodes: [RolloutEpisode],
    snapshotURL: URL?,
    rolloutRoot: URL
) -> [KuyuRegressionWorkerSummary] {
    let grouped = Dictionary(grouping: episodes, by: \.workerIndex)
    return grouped.keys.sorted().map { workerIndex in
        let workerEpisodes = grouped[workerIndex] ?? []
        let rewardSum = workerEpisodes.reduce(0.0) { $0 + $1.rewardSum }
        let episodeCount = workerEpisodes.count
        let rewardAverage = episodeCount > 0 ? rewardSum / Double(episodeCount) : 0
        let durationSeconds = workerEpisodes.reduce(0.0) { $0 + max($1.durationSeconds, 0) }
        let throughput = durationSeconds > 0 ? Double(episodeCount) / durationSeconds : Double(episodeCount)
        return KuyuRegressionWorkerSummary(
            workerIndex: workerIndex,
            snapshotID: snapshotURL?.lastPathComponent,
            rolloutShardPath: rolloutRoot.appendingPathComponent("worker-\(workerIndex)", isDirectory: true).path,
            episodeCount: episodeCount,
            rewardSum: rewardSum,
            rewardAverage: rewardAverage,
            throughput: throughput,
            doneCount: workerEpisodes.filter(\.done).count,
            truncatedCount: workerEpisodes.filter(\.truncated).count,
            failureCount: workerEpisodes.filter { $0.failureReason != nil }.count,
            cancelledCount: workerEpisodes.filter(\.cancelled).count
        )
    }
}

private func regressionSnapshotCompatibilityFailure(
    snapshotURL: URL,
    task: LearningCampaignRolloutTask
) throws -> String? {
    try ManasMLXCheckpointCompatibility(expectedDriveCount: expectedDriveCount(task: task))
        .validate(snapshotURL: snapshotURL)?
        .description
}

private func expectedDriveCount(task: LearningCampaignRolloutTask) -> Int {
    task == .singleLift ? 1 : 4
}

private func regressionTrackName(for suite: Int) -> String {
    switch suite {
    case 6:
        return LongHorizonBenchmarkTrack.longHorizonTask.rawValue
    case 7:
        return LongHorizonBenchmarkTrack.morphologyTransfer.rawValue
    case 8:
        return LongHorizonBenchmarkTrack.disturbanceDelayPartialObservability.rawValue
    default:
        return "unknown"
    }
}

private func simulationTaskMode(from task: LearningCampaignRolloutTask) -> SimulationTaskMode {
    switch task {
    case .attitude:
        return .attitude
    case .lift:
        return .lift
    case .singleLift:
        return .singleLift
    }
}

private func rolloutDefinitionKey(scenarioID: String, seed: UInt64) -> String {
    "\(scenarioID)#\(seed)"
}
