import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLXReferenceQuadrotor
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

struct Rollout: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Collect RL-style environment rollouts over KUY-ATT-1 scenarios."
    )

    @Option(help: "Controller to use: activeAltitudeHold, sensorBaseline, or manasMLX.")
    var controller: ControllerChoice = .activeAltitudeHold

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Number of episodes to collect from KUY-ATT-1.")
    var episodes: Int = 2

    @Option(help: "Task suite to roll out: attitude, lift, or singleLift.")
    var task: RolloutTaskChoice = .attitude

    @Option(help: "M2 scenario suite: 6 long-horizon, 7 morphology transfer, 8 partial-observability/disturbance.")
    var suite: Int?

    @Option(help: "Robot manifest path (optional).")
    var model: String = ""

    @Option(help: "ManasMLX model snapshot directory containing model.json/core.safetensors/reflex.safetensors.")
    var snapshot: String = ""

    @Option(help: "Worker count for parallel rollout. Use 1 for serial.")
    var workers: Int = ParallelRolloutCollector.defaultWorkerCount()

    @Option(name: .customLong("max-steps"), help: "Maximum environment steps per episode. Omit to use scenario duration.")
    var maxSteps: Int?

    @Option(name: .customLong("max-wall-time"), help: "Maximum wall-clock seconds per episode. Omit for no wall-time limit.")
    var maxWallTime: Double?

    @Option(help: "kp gain for baseline controller.")
    var kp: Double = 2.0

    @Option(help: "kd gain for baseline controller.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Option(name: .customLong("motor-rate-limit"), help: "Override the motor-nerve rate limit per second (default: teacher 100, policy 2). Use the policy value (2) to generate teacher demonstrations achievable under the policy's actuator constraints.")
    var motorRateLimit: Double?

    @Option(name: .customLong("motor-smoothing"), help: "Override the motor-nerve smoothing time constant (default: teacher nil, policy 0.08). Pass a negative value to force nil.")
    var motorSmoothing: Double?

    @Option(name: .customLong("export-dataset"), help: "Directory to export rollout dataset.")
    var exportDatasetPath: String?

    @Flag(name: .customLong("training-suite"), help: "Use task-specific training scenarios instead of regression scenarios for dataset bootstrap.")
    var useTrainingSuite: Bool = false

    mutating func run() async throws {
        guard episodes > 0 else {
            throw ValidationError("--episodes must be greater than 0.")
        }
        guard workers > 0 else {
            throw ValidationError("--workers must be greater than 0.")
        }
        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )
        let mode: KuyAtt1BaselineMode = {
            switch controller {
            case .activeAltitudeHold:
                return .teacher
            case .sensorBaseline:
                return .sensor
            case .manasMLX:
                return .teacher
            }
        }()

        let suiteDefinitions = try makeRolloutDefinitions(
            task: task,
            suite: suite,
            episodes: episodes,
            useTrainingSuite: useTrainingSuite
        )
        let requestedEpisodeCount = useTrainingSuite ? max(episodes, suiteDefinitions.count) : episodes
        let definitions = Array(suiteDefinitions.prefix(min(requestedEpisodeCount, suiteDefinitions.count)))
        if definitions.count < requestedEpisodeCount {
            print("[rollout] requested episodes=\(requestedEpisodeCount) available=\(definitions.count); using available KUY-ATT-1 scenarios")
        }

        let loadedRobot = try loadLoadedRobot(modelPath: model)
        let rolloutParameters = try makeRolloutParameters(
            task: task,
            loadedRobot: loadedRobot,
            hoverThrustScale: hoverScale
        )
        let limits = try RolloutRunner.Limits.validated(
            maxStepsPerEpisode: maxSteps,
            maxWallTimeSeconds: maxWallTime
        )
        let resolvedRateLimit = motorRateLimit ?? (mode == .teacher ? 100.0 : 2.0)
        let resolvedSmoothing: Double?
        if let motorSmoothing {
            resolvedSmoothing = motorSmoothing < 0 ? nil : motorSmoothing
        } else {
            resolvedSmoothing = mode == .teacher ? nil : 0.08
        }
        let runner = RolloutRunner(
            parameters: rolloutParameters,
            schedule: schedule,
            determinism: determinism,
            hoverThrustScale: hoverScale,
            loadedRobot: loadedRobot,
            motorNerveRateLimitPerSecond: resolvedRateLimit,
            motorNerveSmoothingTimeConstant: resolvedSmoothing,
            limits: limits
        )
        let policyFactory: any ReferenceQuadrotorPolicyFactory
        switch controller {
        case .manasMLX:
            let trimmed = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ValidationError("--snapshot is required for manasMLX rollout. Shared ManasMLXModelStore rollout is intentionally unsupported.")
            }
            policyFactory = ManasMLXReferenceQuadrotorRolloutPolicyFactory(
                snapshotDirectory: URL(fileURLWithPath: trimmed, isDirectory: true)
            )
        case .activeAltitudeHold, .sensorBaseline:
            policyFactory = KuyAtt1BaselinePolicyFactory(
                parameters: rolloutParameters,
                gains: gains,
                mode: mode
            )
        }

        let collected: [RolloutEpisode]
        if workers == 1 {
            collected = try await runner.run(definitions: definitions, policyFactory: policyFactory)
        } else {
            let collector = try ParallelRolloutCollector(runner: runner, workerCount: workers)
            collected = try await collector.collect(definitions: definitions, policyFactory: policyFactory)
        }

        let summary = RolloutSummary(episodes: collected)
        printRolloutSummary(summary: summary, workers: workers, policyId: policyFactory.policyID)

        if let exportDatasetPath {
            let root = URL(fileURLWithPath: exportDatasetPath, isDirectory: true)
            let writer = TrainingDatasetWriter()
            let definitionsByKey = Dictionary(
                uniqueKeysWithValues: definitions.map { definition in
                    (
                        rolloutDefinitionKey(
                            scenarioId: definition.config.id.rawValue,
                            seed: definition.config.seed.rawValue
                        ),
                        definition
                    )
                }
            )
            for episode in collected {
                guard let definition = definitionsByKey[rolloutDefinitionKey(scenarioId: episode.scenarioId, seed: episode.seed)] else {
                    throw ValidationError("Missing rollout definition for scenario=\(episode.scenarioId) seed=\(episode.seed).")
                }
                let dir = root.appendingPathComponent(safePathComponent(episode.episodeId), isDirectory: true)
                _ = try writer.write(
                    episode: episode,
                    timeStep: definition.config.timeStep.delta,
                    determinismTier: determinism.tier.rawValue,
                    to: dir
                )
            }
            print("[rollout] dataset exported count=\(collected.count) path=\(root.path)")
        }
    }
}

private func printRolloutSummary(summary: RolloutSummary, workers: Int, policyId: String) {
    let averageReward: Double
    if summary.episodeCount > 0 {
        averageReward = summary.rewardSum / Double(summary.episodeCount)
    } else {
        averageReward = 0.0
    }
    print(
        "[rollout] policy=\(policyId) workers=\(workers) episodes=\(summary.episodeCount) rewardSum=\(String(format: "%.6f", summary.rewardSum)) rewardAvg=\(String(format: "%.6f", averageReward)) done=\(summary.doneCount) truncated=\(summary.truncatedCount) failures=\(summary.failureCount) cancelled=\(summary.cancelledCount)"
    )
}

private func rolloutDefinitionKey(scenarioId: String, seed: UInt64) -> String {
    "\(scenarioId)#\(seed)"
}
