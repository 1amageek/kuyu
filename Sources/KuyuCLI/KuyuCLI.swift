import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLX
import KuyuPhysics
import KuyuScenarios
import KuyuTraining
import KuyuUI
import ManasCore

@main
struct KuyuCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kuyu",
        abstract: "Kuyu training world command-line interface.",
        subcommands: [Run.self, Rollout.self, Loop.self, Train.self, Runs.self, Control.self, ProbeRoArmM1.self, TrainRoArmM1JointTargets.self, ProbeManas.self, ProbeManasSuite.self, ProbeCTBRPolicy.self, ProbeCTBRPPOBackend.self, ProbeCTBRRollout.self, WriteCTBRCheckpoint.self, BehaviorCloneCTBR.self, DaggerRelabelCTBR.self, TrainManasCore.self, MixTrainingDatasets.self, EvaluateManasCheckpoint.self, CalibrateManasCheckpoint.self, SelectManasBiasCalibration.self, CheckEnvironments.self, CheckTrainingHarness.self, CheckTrainingHarnessSweep.self, CheckKuyuRegression.self, CheckKuyuRegressionMatrix.self, EvolveManas.self, RunLearningCampaign.self, ValidateLearningCampaign.self, TrainWorldModel.self, ImagineTrain.self, Verify.self, Conformance.self, Doctor.self]
    )
}

enum TierChoice: String, CaseIterable, ExpressibleByArgument {
    case tier0
    case tier1
    case tier2
}

enum ControllerChoice: String, CaseIterable, ExpressibleByArgument {
    case activeAltitudeHold
    case sensorBaseline
    case manasMLX
}

enum RolloutTaskChoice: String, CaseIterable, ExpressibleByArgument {
    case attitude
    case lift
    case singleLift
}

enum LearningCampaignTaskChoice: String, CaseIterable, ExpressibleByArgument {
    case lift
    case singleLift

    var rolloutTask: RolloutTaskChoice {
        switch self {
        case .lift:
            return .lift
        case .singleLift:
            return .singleLift
        }
    }
}

enum EvolutionVariationChoice: String, CaseIterable, ExpressibleByArgument {
    case copy
    case gaussian
}

enum EvolutionEvaluationChoice: String, CaseIterable, ExpressibleByArgument {
    case regression
    case candidateOnly
}

enum EvolutionSearchStrategyChoice: String, CaseIterable, ExpressibleByArgument {
    case genetic
    case antitheticEvolutionStrategy
    case qualityDiversity

    var trainingStrategy: EvolutionSearchStrategy {
        switch self {
        case .genetic:
            return .genetic
        case .antitheticEvolutionStrategy:
            return .antitheticEvolutionStrategy
        case .qualityDiversity:
            return .qualityDiversity
        }
    }
}

enum EvolutionBootstrapSourceChoice: String, CaseIterable, ExpressibleByArgument {
    case checkpoint
    case teacher
    case demonstration
    case none

    var trainingSource: EvolutionBootstrapSource {
        switch self {
        case .checkpoint:
            return .checkpoint
        case .teacher:
            return .teacher
        case .demonstration:
            return .demonstration
        case .none:
            return .none
        }
    }
}

enum EvolutionWorldModelUsageChoice: String, CaseIterable, ExpressibleByArgument {
    case disabled
    case evaluationAssist
    case imaginationAssist

    var trainingUsage: EvolutionWorldModelUsage {
        switch self {
        case .disabled:
            return .disabled
        case .evaluationAssist:
            return .evaluationAssist
        case .imaginationAssist:
            return .imaginationAssist
        }
    }
}

extension LearningCampaignArtifactRetentionMode: @retroactive ExpressibleByArgument {}
extension LearningCampaignTask: @retroactive ExpressibleByArgument {}
extension LearningCampaignTier: @retroactive ExpressibleByArgument {}
extension LearningCampaignVariation: @retroactive ExpressibleByArgument {}
extension AutonomousOperationDomain: @retroactive ExpressibleByArgument {}
extension EvolutionSearchStrategy: @retroactive ExpressibleByArgument {}
extension ReadinessLevel: @retroactive ExpressibleByArgument {}

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run a single KUY-ATT-1 suite.")

    @Option(help: "Controller to use: activeAltitudeHold, sensorBaseline, or manasMLX.")
    var controller: ControllerChoice = .activeAltitudeHold

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path (optional).")
    var model: String = ""

    @Option(help: "World model path override (optional).")
    var world: String = ""

    @Option(help: "Required readiness level.")
    var readiness: ReadinessLevel = .dynamicSimulation

    @Option(help: "kp gain for baseline controller.")
    var kp: Double = 2.0

    @Option(help: "kd gain for baseline controller.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Option(name: .customLong("descending"), help: "Optional descending channels as comma-separated values (e.g. 0.8,0.0,-0.2).")
    var descending: String = ""

    @Option(name: .customLong("descending-program"), help: "Optional descending program as 'time:values;time:values' (e.g. 0:0.4,0,0,0;1.0:0.6,0,0,0).")
    var descendingProgram: String = ""

    @Flag(name: .customLong("no-aux"), help: "Disable aux prediction loss for MLX.")
    var noAux: Bool = false

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
    var noQualityGate: Bool = false

    @Option(name: .customLong("export-logs"), help: "Directory to export logs.")
    var exportLogsPath: String?

    @Option(name: .customLong("export-dataset"), help: "Directory to export training dataset.")
    var exportDatasetPath: String?

    @Flag(help: "Exit with non-zero code when the suite fails.")
    var failOnError: Bool = false

    @MainActor
    mutating func run() async throws {
        let determinism = try makeDeterminism(tier: tier)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )
        let descendingVector = try parseDescendingVector(descending)
        let parsedDescendingProgram = try parseDescendingProgram(descendingProgram)
        if descendingVector != nil, parsedDescendingProgram != nil {
            throw ValidationError("Specify either --descending or --descending-program, not both.")
        }

        let request = SimulationRunRequest(
            controller: controllerSelection(from: controller),
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            robotManifestPath: model,
            worldModelPath: world,
            readinessRequirement: readiness,
            overrideParameters: nil,
            useAux: !noAux,
            useQualityGating: !noQualityGate,
            descendingVector: descendingVector,
            descendingProgram: parsedDescendingProgram
        )
        let output = try await SimulationRunnerService(modelStore: ManasMLXModelStore()).run(request: request)

        printSummary(output: output)

        if let exportLogsPath {
            let dir = URL(fileURLWithPath: exportLogsPath, isDirectory: true)
            _ = try KuyAtt1LogWriter().write(output: output, to: dir)
            print("[logs] exported to \(dir.path)")
        }

        if let exportDatasetPath {
            let dir = URL(fileURLWithPath: exportDatasetPath, isDirectory: true)
            let outputs = try TrainingDatasetExporter().write(output: output, to: dir)
            print("[dataset] exported \(outputs.count) scenarios to \(dir.path)")
        }

        if failOnError && !output.summary.suitePassed {
            throw ExitCode.failure
        }
    }
}

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

struct Loop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run a training loop with ManasMLX.")

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path (optional).")
    var model: String = ""

    @Option(help: "Iterations to run.")
    var iterations: Int = 10

    @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
    var sequenceLength: Int = 16

    @Option(name: .customLong("epochs"), help: "Epochs per iteration.")
    var epochs: Int = 4

    @Option(name: .customLong("lr"), help: "Learning rate.")
    var learningRate: Double = 0.001

    @Flag(name: .customLong("no-aux"), help: "Disable aux prediction loss for MLX.")
    var noAux: Bool = false

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
    var noQualityGate: Bool = false

    @Flag(name: .customLong("stop-on-pass"), help: "Stop the loop once the suite passes.")
    var stopOnPass: Bool = false

    @Option(name: .customLong("dataset-root"), help: "Dataset root directory (optional).")
    var datasetRootPath: String?

    @Option(name: .customLong("save-model"), help: "Directory to save trained model (optional).")
    var saveModelPath: String?

    @Option(name: .customLong("max-batches"), help: "Maximum training batches per iteration. Omit for full training; useful for smoke tests.")
    var maxBatches: Int?

    @Option(help: "kp gain for baseline controller.")
    var kp: Double = 2.0

    @Option(help: "kd gain for baseline controller.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Option(name: .customLong("descending"), help: "Optional descending channels as comma-separated values (e.g. 0.8,0.0,-0.2).")
    var descending: String = ""

    @Option(name: .customLong("descending-program"), help: "Optional descending program as 'time:values;time:values' (e.g. 0:0.4;1.0:0.7).")
    var descendingProgram: String = ""

    @MainActor
    mutating func run() async throws {
        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let parameters = try loadParameters(modelPath: model)
        let embodiment = try loadEmbodiment(modelPath: model)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )
        let descendingVector = try parseDescendingVector(descending)
        let parsedDescendingProgram = try parseDescendingProgram(descendingProgram)
        if descendingVector != nil, parsedDescendingProgram != nil {
            throw ValidationError("Specify either --descending or --descending-program, not both.")
        }

        let datasetRoot: URL
        if let datasetRootPath, !datasetRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            datasetRoot = URL(fileURLWithPath: datasetRootPath, isDirectory: true)
        } else {
            datasetRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-loop-\(UUID().uuidString)", isDirectory: true)
        }
        if let maxBatches, maxBatches <= 0 {
            throw ValidationError("--max-batches must be positive when specified.")
        }

        let request = SimulationRunRequest(
            controller: .manasMLX,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            robotManifestPath: model,
            overrideParameters: model.isEmpty ? nil : parameters,
            useAux: !noAux,
            useQualityGating: !noQualityGate,
            descendingVector: descendingVector,
            descendingProgram: parsedDescendingProgram
        )

        let scenarioStore = ManasMLXModelStore()
        let workerStore = ManasMLXModelStore()
        try MLXRuntimeReadinessService().check()

        let checkpointDirectory = saveModelPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let orchestrator = TrainingRunOrchestrator(
            scenarioExecutor: CLIScenarioExecutor(
                store: scenarioStore,
                parameters: parameters,
                schedule: schedule,
                embodiment: embodiment
            ),
            backend: ManasMLXTrainingBackend(
                runtime: ManasMLXTrainingRuntime(modelStore: workerStore),
                saveDirectory: checkpointDirectory,
                rolloutDatasetLoader: .referenceQuadrotor()
            ),
            convergenceEvaluator: ConvergenceEvaluator(config: .init(minDelta: 0.01))
        )
        let config = TrainingRunConfig(
            mode: .supervised,
            maxIterations: max(1, iterations),
            minDelta: 0.01,
            workerCount: 1,
            enableDatasetExport: true,
            enableTraining: true,
            stopOnPass: stopOnPass,
            parentCheckpointID: nil,
            policyID: "manasMLX"
        )
        let trainingTemplate = TrainingBackendRequest(
            datasetURL: datasetRoot,
            sequenceLength: sequenceLength,
            epochs: epochs,
            learningRate: learningRate,
            useAux: !noAux,
            useQualityGating: !noQualityGate,
            maxBatches: maxBatches
        )
        let shouldStopOnPass = stopOnPass
        let result = await orchestrator.run(
            config: config,
            runRequest: request,
            trainingTemplate: trainingTemplate,
            artifactDirectory: datasetRoot,
            onEvent: { event in
            switch event {
            case .iterationStarted(let iteration):
                print("[loop] iter=\(iteration) run started")
            case .suiteCompleted(let iteration, let output, let score):
                let overshoot = output.summary.aggregate.worstOvershootDegrees ?? -1
                let recovery = output.summary.aggregate.averageRecoveryTime ?? -1
                let hf = output.summary.aggregate.averageHfStabilityScore ?? -1
                print("[loop] iter=\(iteration) score=\(String(format: "%.3f", score)) overshoot=\(String(format: "%.2f", overshoot)) recovery=\(String(format: "%.2f", recovery)) hf=\(String(format: "%.2f", hf))")
                if shouldStopOnPass && output.summary.suitePassed {
                    print("[loop] pass observed; convergence artifacts will determine checkpoint acceptance")
                }
            case .datasetExported(let iteration, let directory, let count):
                print("[loop] iter=\(iteration) dataset exported count=\(count) path=\(directory)")
            case .trainingCompleted(let iteration, let backendResult):
                print("[loop] iter=\(iteration) training loss=\(String(format: "%.6f", backendResult.finalLoss))")
            case .convergenceUpdated(let summary):
                print("[loop] convergence accepted=\(summary.accepted) reason=\(summary.reason)")
            default:
                break
            }
        })
        print("[loop] artifacts path=\(datasetRoot.path)")
        let classification = TrainingRunResultTerminalClassifier().classify(result: result)
        print("[loop] terminal=\(result.manifest.terminalState.rawValue) terminalAcceptance=\(classification.status.rawValue) reason=\(classification.reason)")
    }

    @MainActor
    private func saveCurrentModelIfRequested(store: ManasMLXModelStore, path: String?) throws {
        guard let path else { return }
        let saveDir = URL(fileURLWithPath: path, isDirectory: true)
        try store.saveModel(to: saveDir)
        print("[loop] model saved to \(saveDir.path)")
    }
}

struct ProbeManas: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe-manas",
        abstract: "Run teacher, initial ManasMLX, training, reload, and trained ManasMLX comparison."
    )

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(help: "Task suite to probe: attitude, lift, or singleLift.")
    var task: RolloutTaskChoice = .attitude

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(name: .customLong("source-checkpoint"), help: "Optional source checkpoint directory containing model.json and core.safetensors.")
    var sourceCheckpointPath: String?

    @Option(name: .customLong("artifact-root"), help: "Directory where probe artifacts are written.")
    var artifactRootPath: String?

    @Option(help: "Training iterations.")
    var iterations: Int = 1

    @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
    var sequenceLength: Int = 16

    @Option(name: .customLong("epochs"), help: "Epochs per iteration.")
    var epochs: Int = 1

    @Option(name: .customLong("lr"), help: "Learning rate.")
    var learningRate: Double = 0.001

    @Option(name: .customLong("max-batches"), help: "Maximum training batches for smoke tests.")
    var maxBatches: Int?

    @Option(help: "Worker count for future parallel training probes. Values greater than 1 require --source-checkpoint.")
    var workers: Int = 1

    @Option(name: .customLong("min-delta"), help: "Minimum trained-vs-initial score delta required for probe success.")
    var minDelta: Double = 0

    @Option(help: "kp gain for baseline controller.")
    var kp: Double = 2.0

    @Option(help: "kd gain for baseline controller.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Option(name: .customLong("mlx-seed"), help: "Optional MLX random seed for reproducible probe initialization.")
    var mlxSeed: UInt64?

    @Flag(name: .customLong("no-aux"), help: "Disable aux prediction loss for MLX.")
    var noAux: Bool = false

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
    var noQualityGate: Bool = false

    @MainActor
    mutating func run() async throws {
        guard iterations > 0 else {
            throw ValidationError("--iterations must be greater than 0.")
        }
        guard sequenceLength > 0 else {
            throw ValidationError("--sequence must be greater than 0.")
        }
        guard epochs > 0 else {
            throw ValidationError("--epochs must be greater than 0.")
        }
        if let maxBatches, maxBatches <= 0 {
            throw ValidationError("--max-batches must be positive when specified.")
        }
        guard workers > 0 else {
            throw ValidationError("--workers must be greater than 0.")
        }

        let sourceCheckpointURL = sourceCheckpointPath
            .flatMap { path -> URL? in
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed, isDirectory: true)
            }
        if workers > 1, sourceCheckpointURL == nil {
            throw ValidationError("--workers greater than 1 requires --source-checkpoint so every worker can lease an isolated snapshot.")
        }
        if let mlxSeed {
            ManasMLXRandomSeed.seed(mlxSeed)
            print("[probe] mlxSeed=\(mlxSeed)")
        }
        let preflight = try ManasMLXRuntimeReadinessService().report(
            for: ManasMLXRuntimeReadinessRequest(
                robotManifestPath: model,
                sourceCheckpointURL: sourceCheckpointURL
            )
        )
        print("[probe] preflight mlx=\(preflight.mlxRuntimeReady) robotManifestLoaded=\(preflight.robotManifestLoaded) sourceCheckpointLoadable=\(preflight.sourceCheckpointLoadable)")

        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let parameters = try loadParameters(modelPath: model)
        let embodiment = try loadEmbodiment(modelPath: model)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )
        let taskMode = simulationTaskMode(from: task)
        let artifactRoot: URL
        if let artifactRootPath, !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        } else {
            artifactRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-probe-\(UUID().uuidString)", isDirectory: true)
        }
        let runID = "probe-\(UUID().uuidString)"
        let teacherRequest = SimulationRunRequest(
            controller: .teacherActiveAltitudeHold,
            taskMode: taskMode,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            robotManifestPath: model,
            overrideParameters: model.isEmpty ? nil : parameters,
            useAux: !noAux,
            useQualityGating: !noQualityGate
        )
        let trainingRequest = SimulationRunRequest(
            controller: .manasMLX,
            taskMode: taskMode,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            robotManifestPath: model,
            overrideParameters: model.isEmpty ? nil : parameters,
            useAux: !noAux,
            useQualityGating: !noQualityGate
        )

        let initialStore = ManasMLXModelStore()
        let workerStore = ManasMLXModelStore()
        let trainedStore = ManasMLXModelStore()
        if let sourceCheckpointURL {
            _ = try initialStore.loadModel(from: sourceCheckpointURL)
        }

        let sourceSnapshot = sourceCheckpointURL.map { url in
            TrainingBackendSnapshot(
                snapshotID: "\(runID)-source",
                checkpointID: url.lastPathComponent,
                checkpointURL: url,
                robotManifestID: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : model,
                configHash: model
            )
        }
        let workerPlan: ParallelTrainingWorkerPlan?
        if let sourceCheckpointURL, workers > 1 {
            workerPlan = try await ParallelTrainingWorkerPlanBuilder().build(
                runID: "\(runID)-training",
                workerCount: workers,
                sourceSnapshot: sourceSnapshot,
                rolloutRoot: artifactRoot
                    .appendingPathComponent("training", isDirectory: true)
                    .appendingPathComponent("worker-rollouts", isDirectory: true),
                snapshotProvider: ManasMLXSnapshotProvider(
                    sourceCheckpointURL: sourceCheckpointURL,
                    workerRootURL: artifactRoot
                        .appendingPathComponent("training", isDirectory: true)
                        .appendingPathComponent("worker-snapshots", isDirectory: true),
                    policyID: "manasMLX",
                    robotManifestID: sourceSnapshot?.robotManifestID,
                    configHash: sourceSnapshot?.configHash
                )
            )
            print("[probe] workerPlan workers=\(workerPlan?.workerCount ?? workers)")
        } else {
            workerPlan = nil
        }
        let backend = ManasMLXTrainingBackend(
            runtime: ManasMLXTrainingRuntime(modelStore: workerStore),
            saveDirectory: artifactRoot
                .appendingPathComponent("training", isDirectory: true)
                .appendingPathComponent("candidate-checkpoints", isDirectory: true),
            rolloutDatasetLoader: .referenceQuadrotor()
        )
        let probe = TrainingProbeOrchestrator(
            scenarioExecutor: CLITrainingProbeExecutor(
                teacherRequest: teacherRequest,
                initialStore: initialStore,
                trainedStore: trainedStore,
                parameters: parameters,
                schedule: schedule,
                embodiment: embodiment
            ),
            backend: backend
        )
        let result = await probe.run(
            probeConfig: TrainingProbeConfig(probeID: runID, minScoreDelta: minDelta),
            teacherRequest: teacherRequest,
            trainingRequest: trainingRequest,
            trainingConfig: TrainingRunConfig(
                runID: "\(runID)-training",
                mode: .supervised,
                maxIterations: iterations,
                minDelta: 0.01,
                workerCount: workers,
                enableDatasetExport: true,
                enableTraining: true,
                stopOnPass: false,
                parentCheckpointID: sourceSnapshot?.checkpointID,
                policyID: "manasMLX",
                parallelWorkerPlan: workerPlan
            ),
            trainingTemplate: TrainingBackendRequest(
                datasetURL: artifactRoot,
                sequenceLength: sequenceLength,
                epochs: epochs,
                learningRate: learningRate,
                useAux: !noAux,
                useQualityGating: !noQualityGate,
                maxBatches: maxBatches,
                sourceSnapshot: sourceSnapshot
            ),
            artifactDirectory: artifactRoot
        ) { event in
            switch event {
            case .iterationStarted(let iteration):
                print("[probe] training iter=\(iteration) started")
            case .suiteCompleted(let iteration, _, let score):
                print("[probe] training iter=\(iteration) teacherDatasetScore=\(String(format: "%.3f", score))")
            case .datasetExported(let iteration, let directory, let count):
                print("[probe] training iter=\(iteration) dataset count=\(count) path=\(directory)")
            case .trainingCompleted(let iteration, let backendResult):
                print("[probe] training iter=\(iteration) loss=\(String(format: "%.6f", backendResult.finalLoss))")
            case .convergenceUpdated(let summary):
                print("[probe] convergence accepted=\(summary.accepted) reason=\(summary.reason)")
            default:
                break
            }
        }

        print("[probe] artifacts path=\(artifactRoot.path)")
        print("[probe] terminal=\(result.manifest.terminalState.rawValue)")
        print("[probe] teacherScore=\(String(format: "%.3f", result.comparison.teacherScore)) initialScore=\(String(format: "%.3f", result.comparison.initialScore))")
        if let trainedScore = result.comparison.trainedScore, let scoreDelta = result.comparison.scoreDelta {
            print("[probe] trainedScore=\(String(format: "%.3f", trainedScore)) delta=\(String(format: "%.3f", scoreDelta))")
        } else {
            print("[probe] trainedScore=n/a delta=n/a")
        }
        let validated = try GeneratedTrainingArtifactCompatibilityVerifier().loadProbeArtifacts(from: artifactRoot)
        print("[probe] artifactValid=true trainingRun=\(validated.training.manifest.runID) metrics=\(validated.training.metrics.count)")
        print("[probe] trainingCheckpoint=\(result.comparison.checkpointDecision.rawValue) probeCheckpoint=\(result.probeCheckpointDecision.state.rawValue) reload=\(result.comparison.reloadSucceeded)")
        print("[probe] selectedCheckpoint role=\(result.comparison.selectedCheckpointRole.rawValue) path=\(result.comparison.selectedCheckpointURL?.path ?? "n/a")")
        print("[probe] probeAccepted=\(result.comparison.probeAccepted) reasons=\(result.comparison.probeRejectionReasons.joined(separator: ","))")
    }
}

struct ProbeCTBRPolicy: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe-ctbr-policy",
        abstract: "Run a strict GPU probe for the temporal CTBR actor-critic backend."
    )

    @Option(name: .customLong("batch-size"), help: "Synthetic batch size for the GPU probe.")
    var batchSize: Int = 32

    @Option(name: .customLong("hidden-size"), help: "Actor-critic hidden size.")
    var hiddenSize: Int = 128

    @Option(name: .customLong("epochs"), help: "Training epochs for BC and PPO smoke updates.")
    var epochs: Int = 1

    @Option(help: "Deterministic random seed for synthetic tensor inputs.")
    var seed: UInt64 = 42

    func run() throws {
        let report = try ManasMLXTemporalPolicyProbe().run(
            batchSize: batchSize,
            hiddenSize: hiddenSize,
            epochCount: epochs,
            seed: seed
        )

        print("ctbrPolicyProbe=true")
        print("device=gpu")
        print("batchSize=\(report.batchSize)")
        print("historyLength=\(report.historyLength)")
        print("observationDimension=\(report.observationDimension)")
        print("privilegedDimension=\(report.privilegedDimension)")
        print("hiddenSize=\(report.hiddenSize)")
        print("behaviorCloningActorLoss=\(String(format: "%.6f", report.behaviorCloningActorLoss))")
        print("behaviorCloningCriticLoss=\(String(format: "%.6f", report.behaviorCloningCriticLoss))")
        print("ppoActorLoss=\(String(format: "%.6f", report.ppoActorLoss))")
        print("ppoCriticLoss=\(String(format: "%.6f", report.ppoCriticLoss))")
    }
}

struct ProbeCTBRPPOBackend: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe-ctbr-ppo-backend",
        abstract: "Run the strict CTBR rollout dataset loader and MLX PPO backend, then save a trained Manas bundle."
    )

    enum ProbeError: Error, CustomStringConvertible {
        case outputAlreadyExists(String)
        case invalidCandidateCount(Int)
        case invalidDuration(Double)

        var description: String {
            switch self {
            case .outputAlreadyExists(let path):
                return "output-already-exists: \(path)"
            case .invalidCandidateCount(let count):
                return "invalid-candidate-count: \(count)"
            case .invalidDuration(let duration):
                return "invalid-duration: \(duration)"
            }
        }
    }

    @Option(name: .customLong("artifact-root"), help: "Destination artifact root. Defaults to a temporary directory.")
    var artifactRoot: String = ""

    @Option(name: .customLong("candidates"), help: "Number of CTBR candidates to roll out together on the tensor world.")
    var candidateCount: Int = 8

    @Option(name: .customLong("duration"), help: "Tensor-world rollout duration in seconds.")
    var duration: Double = 1.0

    @Option(name: .customLong("epochs"), help: "PPO update epochs.")
    var epochs: Int = 1

    @Option(name: .customLong("hidden-size"), help: "Temporal actor-critic hidden size.")
    var hiddenSize: Int = 128

    func run() async throws {
        guard candidateCount > 0 else {
            throw ProbeError.invalidCandidateCount(candidateCount)
        }
        guard duration.isFinite, duration > 0 else {
            throw ProbeError.invalidDuration(duration)
        }

        let root = artifactRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("kuyu-ctbr-ppo-backend-\(UUID().uuidString)", isDirectory: true)
            : URL(fileURLWithPath: artifactRoot).standardizedFileURL
        if FileManager.default.fileExists(atPath: root.path) {
            throw ProbeError.outputAlreadyExists(root.path)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sourceCheckpointURL = root.appendingPathComponent("source.manasbundle", isDirectory: true)
        let policyContract = ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract()
        let sourceManifest = try ManasMLXTemporalCheckpointWriter().write(
            request: ManasMLXTemporalCheckpointWriteRequest(
                checkpointURL: sourceCheckpointURL,
                name: "CTBR PPO Probe Source",
                policyContract: policyContract,
                observationContract: ReferenceQuadrotorLearningContracts.temporalCTBRObservationContract(),
                actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
                embodiment: nil,
                hiddenSize: hiddenSize
            )
        )

        let datasetURL = root.appendingPathComponent("tensor-world-rollouts", isDirectory: true)
        let rolloutReport = try ManasMLXReferenceQuadrotorRolloutDatasetExporter().export(
            sourceCheckpointURL: sourceCheckpointURL,
            outputURL: datasetURL,
            candidateCount: candidateCount,
            duration: duration,
            suite: 6
        )

        let checkpointRoot = root.appendingPathComponent("checkpoints", isDirectory: true)
        let backend = await ManasMLXTrainingBackend(
            runtime: ManasMLXTrainingRuntime(modelStore: ManasMLXModelStore()),
            saveDirectory: checkpointRoot,
            rolloutDatasetLoader: .referenceQuadrotor()
        )
        let result = try await backend.trainReinforcement(
            request: ReinforcementTrainingBackendRequest(
                rolloutDatasetURL: datasetURL,
                sourceSnapshot: TrainingBackendSnapshot(
                    snapshotID: "ctbr-ppo-probe-source",
                    checkpointID: sourceManifest.name,
                    checkpointURL: sourceCheckpointURL,
                    robotManifestID: nil,
                    configHash: "ctbr-ppo-probe"
                ),
                workerCount: 1,
                iterations: epochs,
                learningRate: 3e-4,
                algorithm: .actorCritic,
                maxBatches: nil,
                workerPlan: nil
            )
        )

        if let checkpointURL = result.candidateCheckpointURL {
            _ = try ManasMLXTemporalCheckpointReadinessService().report(
                for: ManasMLXTemporalCheckpointReadinessRequest(checkpointURL: checkpointURL)
            )
        }

        print("ctbrPPOBackendProbe=true")
        print("device=gpu")
        print("artifactRoot=\(root.path)")
        print("rolloutDataset=\(datasetURL.path)")
        print("rolloutEpisodes=\(rolloutReport.episodeCount)")
        print("rolloutRewardAverage=\(String(format: "%.6f", rolloutReport.rewardAverage))")
        print("rolloutMinimumStepCount=\(rolloutReport.minimumStepCount)")
        print("rolloutMaximumStepCount=\(rolloutReport.maximumStepCount)")
        print("tensorWorldUsed=\(rolloutReport.tensorWorldUsed)")
        print("candidateCount=\(rolloutReport.candidateCount)")
        print("sourceCheckpoint=\(sourceCheckpointURL.path)")
        print("candidateCheckpointID=\(result.candidateCheckpointID ?? "n/a")")
        print("candidateCheckpoint=\(result.candidateCheckpointURL?.path ?? "n/a")")
        print("rewardAverage=\(String(format: "%.6f", result.rewardAverage))")
        let finalLoss = result.finalLoss ?? Double.nan
        print("finalLoss=\(String(format: "%.6f", finalLoss))")
        print("workerCount=\(result.workerMetrics.count)")
    }
}

struct ProbeCTBRRollout: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe-ctbr-rollout",
        abstract: "Run a GPU tensor-world rollout probe with temporal CTBR policy bundles."
    )

    @Option(name: .customLong("candidates"), help: "Number of CTBR policy candidates to roll out together.")
    var candidateCount: Int = 8

    func run() throws {
        let report = try ManasMLXReferenceQuadrotorRolloutProbe().run(candidateCount: candidateCount)
        print("ctbrRolloutProbe=true")
        print("device=\(report.device)")
        print("policyFamily=\(report.policyFamily)")
        print("actionEncoding=\(report.actionEncoding.rawValue)")
        print("candidateCount=\(report.candidateCount)")
        print("episodeCount=\(report.episodeCount)")
        print("historyLength=\(report.historyLength)")
        print("observationDimension=\(report.observationDimension)")
        print("rewardAverage=\(String(format: "%.6f", report.rewardAverage))")
        print("minimumStepCount=\(report.minimumStepCount)")
        print("maximumStepCount=\(report.maximumStepCount)")
        print("tensorWorldUsed=\(report.tensorWorldUsed)")
    }
}

struct BehaviorCloneCTBR: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "behavior-clone-ctbr",
        abstract: "Behavior-clone a temporal CTBR policy from an active altitude hold rollout dataset to seed a stabilization prior before RL/GA."
    )

    @Option(name: .customLong("source-checkpoint"), help: "Source CTBR .manasbundle providing the policy architecture (obs/history/action dims).")
    var sourceCheckpoint: String = ""

    @Option(name: .customLong("rollout-dataset"), help: "Teacher rollout dataset directory (from `rollout --export-dataset`).")
    var rolloutDataset: String = ""

    @Option(name: .customLong("output"), help: "Destination .manasbundle for the behavior-cloned checkpoint.")
    var output: String = ""

    @Option(name: .customLong("epochs"), help: "Behavior-cloning epochs.")
    var epochs: Int = 50

    @Option(name: .customLong("actor-lr"), help: "Actor learning rate for behavior cloning (the policy config's 3e-4 is too small for supervised BC).")
    var actorLearningRate: Double = 0.001

    @Option(name: .customLong("name"), help: "Bundle display name.")
    var name: String = "Attitude CTBR BC"

    func run() throws {
        let trimmedSource = sourceCheckpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDataset = rolloutDataset.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { throw ValidationError("--source-checkpoint is required.") }
        guard !trimmedDataset.isEmpty else { throw ValidationError("--rollout-dataset is required.") }
        guard !trimmedOutput.isEmpty else { throw ValidationError("--output is required.") }
        let outputURL = URL(fileURLWithPath: trimmedOutput, isDirectory: true)
        guard outputURL.pathExtension == "manasbundle" else {
            throw ValidationError("--output must be a .manasbundle directory.")
        }
        guard epochs > 0 else { throw ValidationError("--epochs must be > 0.") }
        guard actorLearningRate.isFinite, actorLearningRate > 0 else {
            throw ValidationError("--actor-lr must be > 0.")
        }
        let result = try ManasMLXTemporalReinforcementWarmupService(
            rolloutDatasetLoader: .referenceQuadrotor()
        ).behaviorClone(
            sourceCheckpointURL: URL(fileURLWithPath: trimmedSource, isDirectory: true),
            rolloutDatasetURL: URL(fileURLWithPath: trimmedDataset, isDirectory: true),
            epochCount: epochs,
            actorLearningRate: Float(actorLearningRate),
            outputCheckpointURL: outputURL,
            checkpointName: name
        )
        print("behaviorCloneCTBR=true")
        print("output=\(outputURL.path)")
        print("epochs=\(epochs)")
        print("finalActorLoss=\(result.actorLosses.last ?? .nan)")
        print("finalCriticLoss=\(result.criticLosses.last ?? .nan)")
    }
}

struct DaggerRelabelCTBR: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dagger-relabel-ctbr",
        abstract: "Roll a CTBR attitude policy through the A1 scenarios and write a teacher-relabeled (DAgger) dataset covering the policy's visited states."
    )

    @Option(help: "Task suite (attitude only).")
    var task: RolloutTaskChoice = .attitude

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier0

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(name: .customLong("checkpoint"), help: "CTBR policy checkpoint to roll out.")
    var checkpointPath: String

    @Option(name: .customLong("output"), help: "Directory where the teacher-relabeled dataset is written.")
    var outputPath: String

    @Option(help: "kp gain for teacher baseline.")
    var kp: Double = 2.0

    @Option(help: "kd gain for teacher baseline.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for teacher baseline.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Flag(name: .customLong("include-successful"), help: "Relabel all scenarios, not only the policy's failed ones (broader coverage).")
    var includeSuccessful: Bool = false

    @MainActor
    mutating func run() async throws {
        guard task == .attitude else {
            throw ValidationError("dagger-relabel-ctbr currently supports --task attitude only.")
        }
        let checkpointURL = URL(fileURLWithPath: checkpointPath, isDirectory: true)
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
        let profile = try TaskEvaluationProfile.profile(task: task.rawValue)
        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )
        let evaluator = ManasMLXReferenceQuadrotorCheckpointEvaluator(
            config: ManasMLXReferenceQuadrotorCheckpointEvaluatorConfig(
                robotManifestPath: model,
                determinism: determinism,
                schedule: schedule,
                gains: gains,
                useQualityGating: false
            )
        )
        let episodes = try await evaluator.temporalCTBRRolloutEpisodes(
            request: CheckpointEvaluationRequest(
                profile: profile,
                checkpointURL: checkpointURL,
                artifactRoot: outputURL.appendingPathComponent("rollout-artifacts", isDirectory: true)
            )
        )
        let definitions = try KuyAtt1Suite().scenarios()
        let definitionByKey = Dictionary(
            uniqueKeysWithValues: definitions.map {
                ("\($0.config.id.rawValue)#\($0.config.seed.rawValue)", $0)
            }
        )
        let relabeler = AttitudeRecoveryRelabeler()
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        var writtenEpisodes = 0
        var writtenSteps = 0
        for episode in episodes {
            let key = "\(episode.scenarioId)#\(episode.seed)"
            guard let definition = definitionByKey[key] else {
                throw ValidationError("No scenario definition for rolled episode \(key).")
            }
            // includeSuccessful is honored at the loop level: skip episodes the
            // policy already completed cleanly unless broad coverage is requested.
            if !includeSuccessful, episode.failureReason == nil, !episode.done {
                continue
            }
            let relabeled = try relabeler.relabelEpisode(
                episode,
                definition: definition,
                parameters: ReferenceQuadrotorParameters.baseline,
                gains: gains
            )
            let subdir = outputURL.appendingPathComponent(
                "\(episode.scenarioId.replacingOccurrences(of: "/", with: "_"))_seed_\(episode.seed)",
                isDirectory: true
            )
            _ = try TrainingDatasetWriter().write(
                episode: relabeled,
                timeStep: definition.config.timeStep.delta,
                determinismTier: determinism.tier.rawValue,
                to: subdir
            )
            writtenEpisodes += 1
            writtenSteps += relabeled.steps.count
        }
        print("daggerRelabelCTBR=true")
        print("relabeledEpisodes=\(writtenEpisodes)")
        print("relabeledSteps=\(writtenSteps)")
        print("output=\(outputURL.path)")
    }
}

struct WriteCTBRCheckpoint: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "write-ctbr-checkpoint",
        abstract: "Write a strict temporal CTBR Manas bundle for reference quadrotor training."
    )

    enum CommandError: Error, CustomStringConvertible {
        case missingOutput
        case outputParentMissing(String)
        case outputParentIsFile(String)
        case invalidHiddenSize(Int)
        case invalidObservationDimension(Int)
        case invalidHistoryLength(Int)
        case outputMustBeManasBundle(String)
        case outputAlreadyExists(String)

        var description: String {
            switch self {
            case .missingOutput:
                return "missing-output"
            case .outputParentMissing(let path):
                return "output-parent-missing: \(path)"
            case .outputParentIsFile(let path):
                return "output-parent-is-file: \(path)"
            case .invalidHiddenSize(let hiddenSize):
                return "invalid-hidden-size: \(hiddenSize)"
            case .invalidObservationDimension(let value):
                return "invalid-observation-dimension: \(value)"
            case .invalidHistoryLength(let value):
                return "invalid-history-length: \(value)"
            case .outputMustBeManasBundle(let path):
                return "output-must-be-manasbundle: \(path)"
            case .outputAlreadyExists(let path):
                return "output-already-exists: \(path)"
            }
        }
    }

    @Option(name: .customLong("output"), help: "Destination .manasbundle directory.")
    var output: String = ""

    @Option(name: .customLong("name"), help: "Bundle display name.")
    var name: String = "Reference Quadrotor Temporal CTBR"

    @Option(name: .customLong("model"), help: "Optional EmbodimentContract path used to bind embodiment hash/profile metadata.")
    var model: String = ""

    @Option(name: .customLong("hidden-size"), help: "Temporal actor-critic hidden size.")
    var hiddenSize: Int = 256

    @Option(name: .customLong("observation-dimension"), help: "Actor observation channel count. Size to the task's real channel contract (e.g. 6 for attitude) instead of zero-padding into a wider policy. Default 64 (lift privileged observation).")
    var observationDimension: Int = 64

    @Option(name: .customLong("history-length"), help: "Temporal window length. Use 1 for reactive tasks like attitude; 32 for the lift privileged-observation profile.")
    var historyLength: Int = 32

    func run() throws {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            throw CommandError.missingOutput
        }
        guard hiddenSize > 0 else {
            throw CommandError.invalidHiddenSize(hiddenSize)
        }
        guard observationDimension > 0 else {
            throw CommandError.invalidObservationDimension(observationDimension)
        }
        guard historyLength > 0 else {
            throw CommandError.invalidHistoryLength(historyLength)
        }

        let outputURL = URL(fileURLWithPath: trimmedOutput).standardizedFileURL
        guard outputURL.pathExtension == "manasbundle" else {
            throw CommandError.outputMustBeManasBundle(outputURL.path)
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CommandError.outputAlreadyExists(outputURL.path)
        }
        let parentURL = outputURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: parentURL.path, isDirectory: &isDirectory) else {
            throw CommandError.outputParentMissing(parentURL.path)
        }
        guard isDirectory.boolValue else {
            throw CommandError.outputParentIsFile(parentURL.path)
        }

        let embodiment = try loadEmbodiment(modelPath: model)
        let policyContract = ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(
            observationDimension: observationDimension,
            historyLength: historyLength
        )
        let manifest = try ManasMLXTemporalCheckpointWriter().write(
            request: ManasMLXTemporalCheckpointWriteRequest(
                checkpointURL: outputURL,
                name: name,
                policyContract: policyContract,
                observationContract: ReferenceQuadrotorLearningContracts.temporalCTBRObservationContract(),
                actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
                embodiment: embodiment,
                hiddenSize: hiddenSize
            )
        )
        _ = try ManasMLXRuntimeReadinessService().report(
            for: ManasMLXRuntimeReadinessRequest(
                robotManifestPath: model,
                sourceCheckpointURL: outputURL,
                requireSourceCheckpoint: true
            )
        )

        print("ctbrCheckpointWritten=true")
        print("path=\(outputURL.path)")
        print("modelFamily=\(ManasMLXTemporalCheckpointManifest.modelFamily)")
        print("schemaVersion=\(manifest.schemaVersion)")
        print("historyLength=\(manifest.config.batchSpec.historyLength)")
        print("observationDimension=\(manifest.config.batchSpec.observationDimension)")
        print("privilegedDimension=\(manifest.config.batchSpec.privilegedDimension)")
        print("actionDimension=\(manifest.config.batchSpec.actionDimension)")
        print("hiddenSize=\(manifest.config.hiddenSize)")
        print("embodimentBound=\(embodiment != nil)")
    }
}

struct ProbeManasSuite: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe-manas-suite",
        abstract: "Run a matrix of ManasMLX E2E probes and write a suite summary."
    )

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(help: "Comma-separated task list: attitude,lift,singleLift. Defaults to all.")
    var tasks: String = "attitude,lift,singleLift"

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(name: .customLong("source-checkpoint"), help: "Optional source checkpoint directory containing model.json and core.safetensors.")
    var sourceCheckpointPath: String?

    @Option(name: .customLong("artifact-root"), help: "Directory where suite artifacts are written.")
    var artifactRootPath: String?

    @Option(help: "Training iterations per task.")
    var iterations: Int = 1

    @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
    var sequenceLength: Int = 16

    @Option(name: .customLong("epochs"), help: "Epochs per iteration.")
    var epochs: Int = 1

    @Option(name: .customLong("lr"), help: "Learning rate.")
    var learningRate: Double = 0.001

    @Option(name: .customLong("max-batches"), help: "Maximum training batches for smoke tests.")
    var maxBatches: Int?

    @Option(help: "Worker count for future parallel training probes. Values greater than 1 require --source-checkpoint.")
    var workers: Int = 1

    @Option(name: .customLong("min-delta"), help: "Minimum trained-vs-initial score delta required for probe success.")
    var minDelta: Double = 0

    @Option(help: "kp gain for baseline controller.")
    var kp: Double = 2.0

    @Option(help: "kd gain for baseline controller.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Option(name: .customLong("mlx-seed"), help: "Base MLX random seed. Each task increments this value.")
    var mlxSeed: UInt64?

    @Flag(name: .customLong("no-aux"), help: "Disable aux prediction loss for MLX.")
    var noAux: Bool = false

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
    var noQualityGate: Bool = false

    @MainActor
    mutating func run() async throws {
        guard iterations > 0 else {
            throw ValidationError("--iterations must be greater than 0.")
        }
        guard sequenceLength > 0 else {
            throw ValidationError("--sequence must be greater than 0.")
        }
        guard epochs > 0 else {
            throw ValidationError("--epochs must be greater than 0.")
        }
        if let maxBatches, maxBatches <= 0 {
            throw ValidationError("--max-batches must be positive when specified.")
        }
        guard workers > 0 else {
            throw ValidationError("--workers must be greater than 0.")
        }
        let selectedTasks = try parseProbeTasks(tasks)
        let sourceCheckpointURL = sourceCheckpointPath
            .flatMap { path -> URL? in
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed, isDirectory: true)
            }
        if workers > 1, sourceCheckpointURL == nil {
            throw ValidationError("--workers greater than 1 requires --source-checkpoint so every worker can lease an isolated snapshot.")
        }

        let suiteRoot: URL
        if let artifactRootPath, !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            suiteRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        } else {
            suiteRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-probe-suite-\(UUID().uuidString)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: suiteRoot, withIntermediateDirectories: true)

        var entries: [ManasProbeSuiteEntry] = []
        for (taskIndex, task) in selectedTasks.enumerated() {
            let taskRoot = suiteRoot.appendingPathComponent(task.rawValue, isDirectory: true)
            let result = try await runCLIManasProbe(
                task: task,
                tier: tier,
                cutPeriodSteps: cutPeriodSteps,
                model: model,
                sourceCheckpointURL: sourceCheckpointURL,
                artifactRoot: taskRoot,
                iterations: iterations,
                sequenceLength: sequenceLength,
                epochs: epochs,
                learningRate: learningRate,
                maxBatches: maxBatches,
                workers: workers,
                minDelta: minDelta,
                kp: kp,
                kd: kd,
                yawDamping: yawDamping,
                hoverScale: hoverScale,
                useAux: !noAux,
                useQualityGating: !noQualityGate,
                mlxSeed: mlxSeed.map { $0 + UInt64(taskIndex) },
                printEvents: false
            )
            let artifacts = try GeneratedTrainingArtifactCompatibilityVerifier().loadProbeArtifacts(from: taskRoot)
            let entry = ManasProbeSuiteEntry(
                task: task.rawValue,
                artifactPath: taskRoot.path,
                terminalState: result.manifest.terminalState.rawValue,
                trainingCheckpoint: result.comparison.checkpointDecision.rawValue,
                probeCheckpoint: result.probeCheckpointDecision.state.rawValue,
                selectedCheckpointRole: result.comparison.selectedCheckpointRole.rawValue,
                selectedCheckpointPath: result.comparison.selectedCheckpointURL?.path,
                reloadSucceeded: result.comparison.reloadSucceeded,
                teacherScore: result.comparison.teacherScore,
                initialScore: result.comparison.initialScore,
                trainedScore: result.comparison.trainedScore,
                scoreDelta: result.comparison.scoreDelta,
                referenceSatisfied: result.comparison.referenceSatisfied,
                policySatisfied: result.comparison.policySatisfied,
                probeAccepted: result.comparison.probeAccepted,
                probeRejectionReasons: result.comparison.probeRejectionReasons,
                meetsMinimumDelta: result.comparison.meetsMinimumDelta,
                safetyNonRegression: result.comparison.safetyNonRegression,
                teacherDivergenceNonRegression: result.comparison.teacherDivergenceNonRegression,
                teacherDriveDivergenceNonRegression: result.comparison.teacherDriveDivergenceNonRegression,
                teacherMotorDivergenceNonRegression: result.comparison.teacherMotorDivergenceNonRegression,
                teacherAltitudeDivergenceNonRegression: result.comparison.teacherAltitudeDivergenceNonRegression,
                initialTeacherDriveAverageMAE: result.comparison.initialTeacherDriveAverageMAE,
                trainedTeacherDriveAverageMAE: result.comparison.trainedTeacherDriveAverageMAE,
                initialTeacherMotorAverageMAE: result.comparison.initialTeacherMotorAverageMAE,
                trainedTeacherMotorAverageMAE: result.comparison.trainedTeacherMotorAverageMAE,
                initialTeacherFinalAltitudeDelta: result.comparison.initialTeacherFinalAltitudeDelta,
                trainedTeacherFinalAltitudeDelta: result.comparison.trainedTeacherFinalAltitudeDelta,
                trainedFailureReasons: result.trained?.diagnostics.failureReasons ?? [],
                teacherAverageDriveActivation: result.teacher.diagnostics.averageDriveActivation,
                trainedAverageDriveActivation: result.trained?.diagnostics.averageDriveActivation,
                teacherAverageDriveActivationByIndex: result.teacher.diagnostics.averageDriveActivationByIndex,
                trainedAverageDriveActivationByIndex: result.trained?.diagnostics.averageDriveActivationByIndex,
                trainedAverageMotorFinalOutputByIndex: result.trained?.diagnostics.averageMotorFinalOutputByIndex,
                trainedFinalAltitudeZ: result.trained?.diagnostics.finalAltitudeZ,
                trainedFinalVerticalVelocityZ: result.trained?.diagnostics.finalVerticalVelocityZ,
                metricsCount: artifacts.training.metrics.count,
                recoveryRelabelAttempted: result.recoveryRelabelStatus.attempted,
                recoveryRelabelDatasetPath: result.recoveryRelabelStatus.datasetDirectory?.path,
                recoveryRelabelEntryCount: result.recoveryRelabelStatus.report?.relabeledEntryCount,
                recoveryRelabelCutStepCount: result.recoveryRelabelStatus.report?.relabeledCutStepCount,
                failureReason: result.manifest.failureReason
            )
            entries.append(entry)
            print("[probe-suite] task=\(task.rawValue) terminal=\(entry.terminalState) probeAccepted=\(entry.probeAccepted) reasons=\(entry.probeRejectionReasons.joined(separator: ",")) probeCheckpoint=\(entry.probeCheckpoint) reload=\(entry.reloadSucceeded) artifactValid=true")
            print("[probe-suite] selectedCheckpoint role=\(entry.selectedCheckpointRole) path=\(entry.selectedCheckpointPath ?? "n/a")")
            if let trainedMotorMAE = entry.trainedTeacherMotorAverageMAE {
                print("[probe-suite] teacherDivergence motorMAE=\(String(format: "%.6f", trainedMotorMAE)) driveMAE=\(formatOptional(entry.trainedTeacherDriveAverageMAE)) altitudeDelta=\(formatOptional(entry.trainedTeacherFinalAltitudeDelta)) nonRegression=\(entry.teacherDivergenceNonRegression)")
            }
            if entry.recoveryRelabelAttempted {
                print("[probe-suite] recoveryRelabel entries=\(entry.recoveryRelabelEntryCount ?? 0) cutSteps=\(entry.recoveryRelabelCutStepCount ?? 0) path=\(entry.recoveryRelabelDatasetPath ?? "n/a")")
            }
        }

        let summary = ManasProbeSuiteSummary(
            suiteID: "probe-suite-\(UUID().uuidString)",
            startedAt: Date(),
            artifactRoot: suiteRoot.path,
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(summary).write(
            to: suiteRoot.appendingPathComponent("probe-suite-summary.json"),
            options: [.atomic]
        )
        print("[probe-suite] artifacts path=\(suiteRoot.path)")
        print("[probe-suite] completed=\(entries.filter { $0.terminalState == LearningRunTerminalState.completed.rawValue }.count) rejected=\(entries.filter { $0.terminalState == LearningRunTerminalState.rejected.rawValue }.count) failed=\(entries.filter { $0.terminalState == LearningRunTerminalState.failed.rawValue }.count)")
    }
}

struct TrainManasCore: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "train-manas-core",
        abstract: "Train Manas Core from an existing Kuyu/Manas supervised dataset directory."
    )

    @Option(help: "Dataset root containing scenario subdirectories or a single meta.json/records.jsonl pair.")
    var dataset: String

    @Option(help: "Output checkpoint directory.")
    var output: String

    @Option(name: .customLong("source-checkpoint"), help: "Optional source checkpoint directory to continue training from.")
    var sourceCheckpointPath: String?

    @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
    var sequenceLength: Int = 16

    @Option(name: .customLong("epochs"), help: "Epochs.")
    var epochs: Int = 3

    @Option(name: .customLong("lr"), help: "Learning rate.")
    var learningRate: Double = 0.0001

    @Option(name: .customLong("max-batches"), help: "Maximum training batches.")
    var maxBatches: Int?

    @Option(name: .customLong("mlx-seed"), help: "Optional MLX random seed for reproducible initialization.")
    var mlxSeed: UInt64?

    @Flag(name: .customLong("no-aux"), help: "Disable aux prediction loss for MLX.")
    var noAux: Bool = false

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
    var noQualityGate: Bool = false

    @MainActor
    mutating func run() async throws {
        guard sequenceLength > 0 else {
            throw ValidationError("--sequence must be greater than 0.")
        }
        guard epochs > 0 else {
            throw ValidationError("--epochs must be greater than 0.")
        }
        if let maxBatches, maxBatches <= 0 {
            throw ValidationError("--max-batches must be positive when specified.")
        }
        if let mlxSeed {
            ManasMLXRandomSeed.seed(mlxSeed)
            print("[train-manas-core] mlxSeed=\(mlxSeed)")
        }

        let datasetURL = URL(fileURLWithPath: dataset, isDirectory: true)
        let outputURL = URL(fileURLWithPath: output, isDirectory: true)
        let store = ManasMLXModelStore()
        if let sourceCheckpointPath,
           !sourceCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sourceURL = URL(fileURLWithPath: sourceCheckpointPath, isDirectory: true)
            _ = try store.loadModel(from: sourceURL)
            print("[train-manas-core] sourceCheckpoint=\(sourceURL.path)")
        }

        let result = try await store.trainCore(
            datasetURL: datasetURL,
            sequenceLength: sequenceLength,
            learningRate: learningRate,
            epochs: epochs,
            useAux: !noAux,
            useQualityGating: !noQualityGate,
            maxBatches: maxBatches
        )
        let manifest = try store.saveModel(to: outputURL)
        let reloadedStore = ManasMLXModelStore()
        _ = try reloadedStore.loadModel(from: outputURL)
        let reloadedOpenLoop = try reloadedStore.evaluateOpenLoopDriveFit(
            datasetURL: datasetURL,
            sequenceLength: sequenceLength,
            useQualityGating: !noQualityGate,
            maxBatches: maxBatches
        )

        print("[train-manas-core] dataset=\(datasetURL.path)")
        print("[train-manas-core] checkpoint=\(outputURL.path)")
        print("[train-manas-core] model=\(manifest.name) finalLoss=\(String(format: "%.6f", result.finalLoss)) epochs=\(result.epochs)")
        print("[train-manas-core] openLoopDriveMAE=\(formatOptional(result.openLoopDriveMAE)) predictionAverage=\(formatOptional(result.openLoopPredictionAverage)) targetAverage=\(formatOptional(result.openLoopTargetAverage)) firstPrediction=\(formatOptional(result.openLoopFit?.firstPrediction)) firstTarget=\(formatOptional(result.openLoopFit?.firstTarget))")
        print("[train-manas-core] reloadedOpenLoopDriveMAE=\(formatOptional(reloadedOpenLoop?.meanAbsoluteError)) predictionAverage=\(formatOptional(reloadedOpenLoop?.predictionAverage)) targetAverage=\(formatOptional(reloadedOpenLoop?.targetAverage)) firstPrediction=\(formatOptional(reloadedOpenLoop?.firstPrediction)) firstTarget=\(formatOptional(reloadedOpenLoop?.firstTarget))")
    }
}

struct MixTrainingDatasets: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mix-training-datasets",
        abstract: "Mix multiple Kuyu/Manas supervised dataset roots into one training dataset root."
    )

    @Option(name: .customLong("input"), help: "Input dataset root. Repeat this option for multiple roots.")
    var inputs: [String] = []

    @Option(help: "Output mixed dataset root.")
    var output: String

    mutating func run() throws {
        guard !inputs.isEmpty else {
            throw ValidationError("At least one --input is required.")
        }
        let sourceURLs = inputs.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let outputURL = URL(fileURLWithPath: output, isDirectory: true)
        let manifest = try TrainingDatasetMixer().mix(sources: sourceURLs, to: outputURL)
        print("[mix-training-datasets] output=\(outputURL.path)")
        print("[mix-training-datasets] datasets=\(manifest.datasetCount) records=\(manifest.totalRecordCount)")
        for source in manifest.sources {
            print("[mix-training-datasets] sourceIndex=\(source.index) datasets=\(source.copiedDatasetCount) records=\(source.copiedRecordCount) path=\(source.path)")
        }
    }
}

struct EvaluateManasCheckpoint: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "evaluate-manas-checkpoint",
        abstract: "Evaluate a ManasMLX checkpoint against a teacher baseline without additional training."
    )

    @Option(help: "Task suite to evaluate: attitude, lift, or singleLift.")
    var task: RolloutTaskChoice = .attitude

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(name: .customLong("checkpoint"), help: "Checkpoint directory containing model.json, core.safetensors, and reflex.safetensors.")
    var checkpointPath: String

    @Option(name: .customLong("artifact-root"), help: "Directory where evaluation artifacts are written.")
    var artifactRootPath: String

    @Option(help: "kp gain for teacher baseline.")
    var kp: Double = 2.0

    @Option(help: "kd gain for teacher baseline.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for teacher baseline.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for ManasMLX evaluation.")
    var noQualityGate: Bool = false

    @Flag(name: .customLong("require-policy-pass"), help: "Exit non-zero unless the typed checkpoint evaluation artifact passes strict policy validation.")
    var requirePolicyPass: Bool = false

    @MainActor
    mutating func run() async throws {
        let checkpointURL = URL(fileURLWithPath: checkpointPath, isDirectory: true)
        let artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        let profile = try TaskEvaluationProfile.profile(task: task.rawValue)
        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )
        let evaluator = ManasMLXReferenceQuadrotorCheckpointEvaluator(
            config: ManasMLXReferenceQuadrotorCheckpointEvaluatorConfig(
                robotManifestPath: model,
                determinism: determinism,
                schedule: schedule,
                gains: gains,
                useQualityGating: !noQualityGate
            )
        )
        let summary = try await evaluator.evaluateCheckpoint(
            request: CheckpointEvaluationRequest(
                profile: profile,
                checkpointURL: checkpointURL,
                artifactRoot: artifactRoot
            )
        )
        let verifiedArtifact = try GeneratedTrainingArtifactCompatibilityVerifier().loadCheckpointEvaluationArtifact(
            CheckpointEvaluationArtifactCompatibilityRequest(
                artifactDirectory: artifactRoot,
                expectedProfile: profile,
                expectedCheckpointPath: checkpointURL.path,
                requiresPolicyPass: requirePolicyPass
            )
        )
        let g1AcceptanceReport = try evaluateCheckpointAcceptanceIfNeeded(
            profile: profile,
            artifact: verifiedArtifact,
            artifactRoot: artifactRoot
        )

        print("[evaluate-manas-checkpoint] task=\(summary.task) profile=\(summary.profileID) policyPassed=\(summary.policyPassed) score=\(String(format: "%.6f", summary.policyScore)) teacherScore=\(String(format: "%.6f", summary.teacherScore))")
        print("[evaluate-manas-checkpoint] motorMAE=\(formatOptional(summary.motorMAE)) driveMAE=\(formatOptional(summary.driveMAE)) finalAltitudeDelta=\(formatOptional(summary.finalAltitudeDelta)) failures=\(summary.failureReasons.joined(separator: ","))")
        if let g1AcceptanceReport {
            print("[evaluate-manas-checkpoint] g1Acceptance accepted=\(g1AcceptanceReport.accepted) taskPassRate=\(String(format: "%.6f", g1AcceptanceReport.taskPassRate)) safetyViolationRate=\(String(format: "%.6f", g1AcceptanceReport.safetyViolationRate)) failures=\(g1AcceptanceReport.failureReasons.joined(separator: ",")) artifact=\(artifactRoot.appendingPathComponent(ReferenceQuadrotorG1AttitudeAcceptanceReport.fileName).path)")
        }
        if let diagnostics = summary.diagnostics {
            print("[evaluate-manas-checkpoint] diagnostics worstAltitudeDelta=\(formatOptional(diagnostics.worstFinalAltitudeDelta)) worstVzDelta=\(formatOptional(diagnostics.worstFinalVerticalVelocityDelta)) earliestAltitudeDivergence=\(formatOptional(diagnostics.earliestAltitudeDivergenceTime))")
            if let failed = diagnostics.scenarioComparisons.first(where: { $0.policyFailureReason != nil }) {
                print("[evaluate-manas-checkpoint] firstFailedScenario id=\(failed.scenarioID) seed=\(failed.seed) reason=\(failed.policyFailureReason ?? "n/a") failureTime=\(formatOptional(failed.policyFailureTime)) motorMAE=\(formatOptional(failed.motorOutputMAE)) initialDrive=\(formatOptional(failed.policyInitialDriveActivation)) earlyDriveAvg=\(formatOptional(failed.policyEarlyDriveActivationAverage)) teacherEarlyDriveAvg=\(formatOptional(failed.teacherEarlyDriveActivationAverage))")
            }
        }
        print("[evaluate-manas-checkpoint] artifacts path=\(artifactRoot.path)")
    }

    private func evaluateCheckpointAcceptanceIfNeeded(
        profile: TaskEvaluationProfile,
        artifact: CheckpointEvaluationArtifact,
        artifactRoot: URL
    ) throws -> ReferenceQuadrotorG1AttitudeAcceptanceReport? {
        try ReferenceQuadrotorCheckpointEvaluationAcceptanceService()
            .evaluate(request: ReferenceQuadrotorCheckpointEvaluationAcceptanceRequest(
                profile: profile,
                artifact: artifact,
                artifactRoot: artifactRoot
            ))
            .g1Attitude
    }
}

struct CalibrateManasCheckpoint: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calibrate-manas-checkpoint",
        abstract: "Create a calibrated ManasMLX checkpoint by applying a raw drive-head bias delta."
    )

    @Option(name: .customLong("source-checkpoint"), help: "Source checkpoint directory.")
    var sourceCheckpointPath: String

    @Option(name: .customLong("output"), help: "Output checkpoint directory.")
    var outputPath: String

    @Option(name: .customLong("raw-bias-delta"), help: "Raw drive-head bias delta to apply before tanh.")
    var rawBiasDelta: Double

    mutating func run() throws {
        let sourceURL = URL(fileURLWithPath: sourceCheckpointPath, isDirectory: true)
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
        let summary = try ManasMLXCheckpointBiasCalibrationService().calibrate(
            ManasMLXCheckpointBiasCalibrationRequest(
                sourceCheckpointURL: sourceURL,
                outputCheckpointURL: outputURL,
                rawBiasDelta: rawBiasDelta,
                summaryArtifactURL: ManasMLXCheckpointBiasCalibrationService.defaultSummaryURL(
                    for: outputURL
                )
            )
        )
        print("[calibrate-manas-checkpoint] source=\(summary.sourceCheckpointPath)")
        print("[calibrate-manas-checkpoint] output=\(summary.outputCheckpointPath)")
        print("[calibrate-manas-checkpoint] rawBiasDelta=\(String(format: "%.6f", summary.rawBiasDelta))")
    }
}

struct SelectManasBiasCalibration: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "select-manas-bias-calibration",
        abstract: "Evaluate calibrated ManasMLX bias candidates with the typed Kuyu regression gate."
    )

    @Option(name: .customLong("source-checkpoint"), help: "Source checkpoint directory.")
    var sourceCheckpointPath: String

    @Option(name: .customLong("artifact-root"), help: "Directory where calibration selection artifacts are written.")
    var artifactRootPath: String

    @Option(help: "Task suite to evaluate: lift or singleLift.")
    var task: LearningCampaignTaskChoice = .singleLift

    @Option(help: "Comma-separated M2 suite list: 6,7,8.")
    var suites: String = "6"

    @Option(help: "Episodes per suite track.")
    var episodes: Int = 1

    @Option(help: "Worker count for rollout regression.")
    var workers: Int = 1

    @Option(help: "Comma-separated raw drive-head bias deltas.")
    var deltas: String = "-0.016,-0.0152,-0.0148,-0.01465,-0.0146,-0.01455,-0.0145,-0.0144,-0.0143,-0.0142,-0.0140,-0.0138,-0.0132,-0.0125,-0.0115,-0.0105,-0.0095,-0.0085,-0.0075,-0.0065"

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(help: "kp gain for baseline controller.")
    var kp: Double = 2.0

    @Option(help: "kd gain for baseline controller.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Option(name: .customLong("min-reward-average"), help: "Override the task default minimum reward average required for every rollout track.")
    var minimumRewardAverage: Double?

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for ManasMLX rollout.")
    var noQualityGate: Bool = false

    @MainActor
    mutating func run() async throws {
        guard episodes > 0 else {
            throw ValidationError("--episodes must be greater than 0.")
        }
        guard workers > 0 else {
            throw ValidationError("--workers must be greater than 0.")
        }
        if let minimumRewardAverage, !minimumRewardAverage.isFinite {
            throw ValidationError("--min-reward-average must be finite when specified.")
        }

        let sourceCheckpointURL = URL(fileURLWithPath: sourceCheckpointPath, isDirectory: true)
        let artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        try createFreshArtifactRoot(artifactRoot)

        let rawBiasDeltas = try parseRawBiasDeltas(deltas)
        let selectedSuites = try parseCalibrationSuites(suites)
        let rolloutTask = task.rolloutTask
        let profile = try TaskEvaluationProfile.profile(task: rolloutTask.rawValue)
        if noQualityGate && profile.requiresParentCheckpointEvaluation {
            throw ValidationError("--no-quality-gate is not allowed for \(profile.task) calibration selection.")
        }
        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )
        let checkpointEvaluator = ManasMLXReferenceQuadrotorCheckpointEvaluator(
            config: ManasMLXReferenceQuadrotorCheckpointEvaluatorConfig(
                robotManifestPath: model,
                determinism: determinism,
                schedule: schedule,
                gains: gains,
                useQualityGating: !noQualityGate
            )
        )
        let selectedTasks = [simulationTaskMode(from: rolloutTask)]

        var candidates: [ReferenceQuadrotorBiasCalibrationCandidateEvaluation] = []
        let calibrationService = ManasMLXCheckpointBiasCalibrationService()
        for rawBiasDelta in rawBiasDeltas {
            let candidateID = safePathComponent("bias-\(String(format: "%.6f", rawBiasDelta))")
            let candidateCheckpointURL = artifactRoot
                .appendingPathComponent("candidate-checkpoints", isDirectory: true)
                .appendingPathComponent(candidateID, isDirectory: true)
            _ = try calibrationService.calibrate(
                ManasMLXCheckpointBiasCalibrationRequest(
                    sourceCheckpointURL: sourceCheckpointURL,
                    outputCheckpointURL: candidateCheckpointURL,
                    rawBiasDelta: rawBiasDelta
                )
            )

            let regressionRoot = artifactRoot
                .appendingPathComponent("candidate-regressions", isDirectory: true)
                .appendingPathComponent(candidateID, isDirectory: true)
            let regressionSummary = try await runKuyuRegression(
                controller: .manasMLX,
                snapshotURL: candidateCheckpointURL,
                tier: tier,
                cutPeriodSteps: cutPeriodSteps,
                tasks: selectedTasks,
                suites: selectedSuites,
                episodes: episodes,
                workers: workers,
                maxSteps: nil,
                maxWallTime: nil,
                model: model,
                artifactRoot: regressionRoot,
                kp: kp,
                kd: kd,
                yawDamping: yawDamping,
                hoverScale: hoverScale,
                failOnTruncation: profile.failOnTruncation,
                minimumRewardAverage: minimumRewardAverage,
                useQualityGating: !noQualityGate
            )
            let evaluationRoot = artifactRoot
                .appendingPathComponent("candidate-checkpoint-evaluations", isDirectory: true)
                .appendingPathComponent(candidateID, isDirectory: true)
            let checkpointEvaluationReasons: [String]
            let checkpointEvaluationPassed: Bool
            do {
                _ = try await checkpointEvaluator.evaluateCheckpoint(
                    request: CheckpointEvaluationRequest(
                        profile: profile,
                        checkpointURL: candidateCheckpointURL,
                        artifactRoot: evaluationRoot
                    )
                )
                do {
                    _ = try GeneratedTrainingArtifactCompatibilityVerifier().loadCheckpointEvaluationArtifact(
                        CheckpointEvaluationArtifactCompatibilityRequest(
                            artifactDirectory: evaluationRoot,
                            expectedProfile: profile,
                            expectedCheckpointPath: candidateCheckpointURL.path,
                            requiresPolicyPass: true
                        )
                    )
                    checkpointEvaluationPassed = true
                    checkpointEvaluationReasons = []
                } catch {
                    checkpointEvaluationPassed = false
                    checkpointEvaluationReasons = [String(describing: error)]
                }
            } catch {
                checkpointEvaluationPassed = false
                checkpointEvaluationReasons = [String(describing: error)]
            }
            candidates.append(
                ReferenceQuadrotorBiasCalibrationCandidateEvaluation(
                    rawBiasDelta: rawBiasDelta,
                    checkpointURL: candidateCheckpointURL,
                    regressionRoot: regressionRoot,
                    checkpointEvaluationRoot: evaluationRoot,
                    regressionSummary: regressionSummary,
                    checkpointEvaluationPassed: checkpointEvaluationPassed,
                    checkpointEvaluationReasons: checkpointEvaluationReasons
                )
            )
        }

        let selectionService = ReferenceQuadrotorBiasCalibrationSelectionService()
        let summary = try selectionService.summarize(
            ReferenceQuadrotorBiasCalibrationSelectionRequest(
                sourceCheckpointURL: sourceCheckpointURL,
                task: rolloutTask.rawValue,
                suites: selectedSuites,
                episodes: episodes,
                workers: workers,
                candidates: candidates
            )
        )
        let selectedCandidate = selectionService.selectedCandidate(in: summary)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(summary).write(
            to: artifactRoot.appendingPathComponent("bias-calibration-selection.json"),
            options: [.atomic]
        )

        if let selectedCandidate {
            print("[select-manas-bias-calibration] selected=true accepted=\(selectedCandidate.accepted) delta=\(String(format: "%.6f", selectedCandidate.rawBiasDelta)) checkpoint=\(selectedCandidate.checkpointPath)")
        } else {
            print("[select-manas-bias-calibration] selected=false accepted=false")
        }
        print("[select-manas-bias-calibration] artifacts path=\(artifactRoot.path)")
    }
}

private func createFreshArtifactRoot(_ artifactRoot: URL) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: artifactRoot.path) {
        let contents = try fileManager.contentsOfDirectory(
            at: artifactRoot,
            includingPropertiesForKeys: nil
        )
        guard contents.isEmpty else {
            throw ValidationError("--artifact-root must be empty: \(artifactRoot.path)")
        }
    }
    try fileManager.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
}

private func parseRawBiasDeltas(_ raw: String) throws -> [Double] {
    let values = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !values.isEmpty else {
        throw ValidationError("--deltas must include at least one raw bias delta.")
    }
    var seen: Set<Double> = []
    var parsed: [Double] = []
    for value in values {
        guard let delta = Double(value), delta.isFinite else {
            throw ValidationError("--deltas contains a non-finite value: \(value)")
        }
        if seen.insert(delta).inserted {
            parsed.append(delta)
        }
    }
    return parsed
}

private func parseCalibrationSuites(_ raw: String) throws -> [Int] {
    let values = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !values.isEmpty else {
        throw ValidationError("--suites must include at least one suite.")
    }
    var seenSuites = Set<Int>()
    return try values.map { value in
        guard let suite = Int(value), (0...8).contains(suite) else {
            throw ValidationError("--suites supports 0–8 (attitude 0–5 = A1 conformance suites, 6–8 = long-horizon tracks).")
        }
        guard seenSuites.insert(suite).inserted else {
            throw ValidationError("--suites contains a duplicate suite: \(suite)")
        }
        return suite
    }
}

private func formatOptional(_ value: Double?) -> String {
    guard let value else {
        return "n/a"
    }
    return String(format: "%.6f", value)
}

private struct ManasProbeSuiteSummary: Codable {
    let suiteID: String
    let startedAt: Date
    let artifactRoot: String
    let entries: [ManasProbeSuiteEntry]
}

private struct ManasProbeSuiteEntry: Codable {
    let task: String
    let artifactPath: String
    let terminalState: String
    let trainingCheckpoint: String
    let probeCheckpoint: String
    let selectedCheckpointRole: String
    let selectedCheckpointPath: String?
    let reloadSucceeded: Bool
    let teacherScore: Double
    let initialScore: Double
    let trainedScore: Double?
    let scoreDelta: Double?
    let referenceSatisfied: Bool
    let policySatisfied: Bool
    let probeAccepted: Bool
    let probeRejectionReasons: [String]
    let meetsMinimumDelta: Bool
    let safetyNonRegression: Bool
    let teacherDivergenceNonRegression: Bool
    let teacherDriveDivergenceNonRegression: Bool
    let teacherMotorDivergenceNonRegression: Bool
    let teacherAltitudeDivergenceNonRegression: Bool
    let initialTeacherDriveAverageMAE: Double?
    let trainedTeacherDriveAverageMAE: Double?
    let initialTeacherMotorAverageMAE: Double?
    let trainedTeacherMotorAverageMAE: Double?
    let initialTeacherFinalAltitudeDelta: Double?
    let trainedTeacherFinalAltitudeDelta: Double?
    let trainedFailureReasons: [String]
    let teacherAverageDriveActivation: Double?
    let trainedAverageDriveActivation: Double?
    let teacherAverageDriveActivationByIndex: [Double]?
    let trainedAverageDriveActivationByIndex: [Double]?
    let trainedAverageMotorFinalOutputByIndex: [Double]?
    let trainedFinalAltitudeZ: Double?
    let trainedFinalVerticalVelocityZ: Double?
    let metricsCount: Int
    let recoveryRelabelAttempted: Bool
    let recoveryRelabelDatasetPath: String?
    let recoveryRelabelEntryCount: Int?
    let recoveryRelabelCutStepCount: Int?
    let failureReason: String?
}

struct CheckEnvironments: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check-environments",
        abstract: "Validate Kuyu teacher environments before Manas training."
    )

    @Option(help: "Comma-separated task list: attitude,lift,singleLift. Defaults to all.")
    var tasks: String = "attitude,lift,singleLift"

    @Option(help: "Baseline controller to validate: activeAltitudeHold or sensorBaseline.")
    var controller: ControllerChoice = .activeAltitudeHold

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(name: .customLong("artifact-root"), help: "Directory where readiness artifacts are written.")
    var artifactRootPath: String?

    @Option(help: "kp gain for baseline controller.")
    var kp: Double = 2.0

    @Option(help: "kd gain for baseline controller.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Flag(name: .customLong("fail-on-not-ready"), help: "Exit with non-zero status if any environment is not ready.")
    var failOnNotReady: Bool = false

    @MainActor
    mutating func run() async throws {
        let selectedTasks = try parseProbeTasks(tasks).map(simulationTaskMode(from:))
        let selectedController = controllerSelection(from: controller)
        guard selectedController != .manasMLX else {
            throw ValidationError("check-environments validates baseline environments only. Use activeAltitudeHold or sensorBaseline.")
        }

        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let parameters = try loadParameters(modelPath: model)
        let embodiment = try loadEmbodiment(modelPath: model)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )
        let artifactRoot: URL
        if let artifactRootPath, !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        } else {
            artifactRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-environment-readiness-\(UUID().uuidString)", isDirectory: true)
        }

        let report = try await ReferenceQuadrotorEnvironmentReadinessChecker().check(
            tasks: selectedTasks,
            controller: selectedController,
            parameters: parameters,
            schedule: schedule,
            determinism: determinism,
            gains: gains,
            robotManifestPath: model,
            embodiment: embodiment,
            artifactRoot: artifactRoot
        )

        for task in report.tasks {
            print("[env] task=\(task.task) ready=\(task.ready) passed=\(task.suitePassed) score=\(String(format: "%.3f", task.score)) actionCoverage=\(String(format: "%.3f", task.scenarioActionCoverage)) dataset=\(task.datasetScenarioCount)/\(task.scenarioCount) failures=\(task.failureCount)")
            if !task.failureReasons.isEmpty {
                print("[env] task=\(task.task) reasons=\(task.failureReasons.joined(separator: " | "))")
            }
        }
        print("[env] artifacts path=\(artifactRoot.path)")
        print("[env] allReady=\(report.allReady)")

        if failOnNotReady && !report.allReady {
            throw ExitCode.failure
        }
    }
}

struct CheckTrainingHarness: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check-training-harness",
        abstract: "Run Kuyu environment readiness and a ManasMLX supervised E2E training probe."
    )

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(name: .customLong("artifact-root"), help: "Directory where harness artifacts are written.")
    var artifactRootPath: String?

    @Option(name: .customLong("source-checkpoint"), help: "Optional source checkpoint directory to continue probe attempts from.")
    var sourceCheckpointPath: String?

    @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
    var sequenceLength: Int = 16

    @Option(name: .customLong("epochs"), help: "Epochs for the supervised ManasMLX probe.")
    var epochs: Int = 40

    @Option(name: .customLong("lr"), help: "Learning rate for the supervised ManasMLX probe.")
    var learningRate: Double = 0.001

    @Option(name: .customLong("max-batches"), help: "Maximum training batches for the supervised ManasMLX probe.")
    var maxBatches: Int = 64

    @Option(help: "Maximum probe attempts per task. Each attempt writes separate artifacts.")
    var attempts: Int = 3

    @Option(name: .customLong("recovery-repeat"), help: "Repeat recovery relabel datasets this many times when mixing retry training data.")
    var recoveryRepeat: Int = 1

    @Option(name: .customLong("mlx-seed"), help: "Base MLX random seed. Each retry increments this value.")
    var mlxSeed: UInt64 = 10_000

    @Option(help: "kp gain for baseline controller.")
    var kp: Double = 2.0

    @Option(help: "kd gain for baseline controller.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Flag(name: .customLong("include-lift-probe"), help: "Also run a lift probe. The default E2E learning gate is singleLift.")
    var includeLiftProbe: Bool = false

    @Flag(name: .customLong("require-task-solved"), help: "Require the trained policy to satisfy the full task suite, not only the harness smoke gate.")
    var requireTaskSolved: Bool = false

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
    var noQualityGate: Bool = false

    @MainActor
    mutating func run() async throws {
        guard sequenceLength > 0 else {
            throw ValidationError("--sequence must be greater than 0.")
        }
        guard epochs > 0 else {
            throw ValidationError("--epochs must be greater than 0.")
        }
        if maxBatches <= 0 {
            throw ValidationError("--max-batches must be positive when specified.")
        }
        guard attempts > 0 else {
            throw ValidationError("--attempts must be greater than 0.")
        }
        guard recoveryRepeat > 0 else {
            throw ValidationError("--recovery-repeat must be greater than 0.")
        }

        let artifactRoot: URL
        if let artifactRootPath, !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        } else {
            artifactRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-training-harness-\(UUID().uuidString)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)

        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let parameters = try loadParameters(modelPath: model)
        let embodiment = try loadEmbodiment(modelPath: model)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )

        let environmentRoot = artifactRoot.appendingPathComponent("environment-readiness", isDirectory: true)
        let environmentReport = try await ReferenceQuadrotorEnvironmentReadinessChecker().check(
            tasks: [.lift, .singleLift],
            controller: .teacherActiveAltitudeHold,
            parameters: parameters,
            schedule: schedule,
            determinism: determinism,
            gains: gains,
            robotManifestPath: model,
            embodiment: embodiment,
            artifactRoot: environmentRoot
        )
        for task in environmentReport.tasks {
            print("[harness] env task=\(task.task) ready=\(task.ready) score=\(String(format: "%.3f", task.score)) dataset=\(task.datasetScenarioCount)/\(task.scenarioCount)")
        }
        guard environmentReport.allReady else {
            let summary = CheckTrainingHarnessSummary(
                artifactRoot: artifactRoot.path,
                environmentReady: false,
                probes: [],
                selectedCandidate: nil,
                allPassed: false
            )
            try writeHarnessSummary(summary, to: artifactRoot)
            print("[harness] artifacts path=\(artifactRoot.path)")
            throw ExitCode.failure
        }

        var probeTasks: [RolloutTaskChoice] = [.singleLift]
        if includeLiftProbe {
            probeTasks.insert(.lift, at: 0)
        }
        let initialSourceCheckpointURL = sourceCheckpointURL(from: sourceCheckpointPath)
        let harnessGateService = ReferenceQuadrotorTrainingHarnessGateService()

        var probeEntries: [CheckTrainingHarnessProbeEntry] = []
        for task in probeTasks {
            var taskAccepted = false
            var currentSourceCheckpointURL = initialSourceCheckpointURL
            var recoveryDatasetURLs: [URL] = []
            for attempt in 1...attempts {
                let taskRoot = artifactRoot.appendingPathComponent(
                    "probe-\(task.rawValue)-attempt-\(attempt)",
                    isDirectory: true
                )
                let result = try await runCLIManasProbe(
                    task: task,
                    tier: tier,
                    cutPeriodSteps: cutPeriodSteps,
                    model: model,
                    sourceCheckpointURL: currentSourceCheckpointURL,
                    artifactRoot: taskRoot,
                    iterations: 1,
                    sequenceLength: sequenceLength,
                    epochs: epochs,
                    learningRate: learningRate,
                    maxBatches: maxBatches,
                    workers: 1,
                    minDelta: 0,
                    kp: kp,
                    kd: kd,
                    yawDamping: yawDamping,
                    hoverScale: hoverScale,
                    useAux: false,
                    useQualityGating: !noQualityGate,
                    mlxSeed: mlxSeed + UInt64(attempt - 1),
                    additionalDatasetURLs: recoveryDatasetURLs,
                    additionalDatasetRepeatCount: recoveryRepeat,
                    printEvents: true
                )
                let repairSourceCheckpointURL = harnessGateService.repairSourceCheckpointURL(result: result)
                currentSourceCheckpointURL = repairSourceCheckpointURL
                if let recoveryDatasetURL = harnessGateService.acceptedRecoveryDatasetURL(result: result) {
                    recoveryDatasetURLs.append(recoveryDatasetURL)
                }
                let artifacts = try GeneratedTrainingArtifactCompatibilityVerifier().loadProbeArtifacts(from: taskRoot)
                let taskSolved = harnessGateService.taskSolved(result: result)
                let harnessSatisfied = harnessGateService.satisfied(result: result)
                let gateReport = harnessGateService.report(
                    result: result,
                    requireTaskSolved: requireTaskSolved,
                    postRegression: nil
                )
                let accepted = gateReport.accepted
                let entry = CheckTrainingHarnessProbeEntry(
                    task: task.rawValue,
                    attempt: attempt,
                    artifactPath: taskRoot.path,
                    terminalState: result.manifest.terminalState.rawValue,
                    trainingCheckpoint: result.comparison.checkpointDecision.rawValue,
                    probeCheckpoint: result.probeCheckpointDecision.state.rawValue,
                    selectedCheckpointRole: result.comparison.selectedCheckpointRole.rawValue,
                    selectedCheckpointPath: result.comparison.selectedCheckpointURL?.path,
                    repairSourceCheckpointPath: repairSourceCheckpointURL?.path,
                    reloadSucceeded: result.comparison.reloadSucceeded,
                    teacherScore: result.comparison.teacherScore,
                    initialScore: result.comparison.initialScore,
                    trainedScore: result.comparison.trainedScore,
                    scoreDelta: result.comparison.scoreDelta,
                    policySatisfied: result.comparison.policySatisfied,
                    harnessSatisfied: harnessSatisfied,
                    taskSolved: taskSolved,
                    trainedFailureReasons: result.trained?.diagnostics.failureReasons ?? [],
                    trainedAverageDriveActivation: result.trained?.diagnostics.averageDriveActivation,
                    teacherAverageDriveActivation: result.teacher.diagnostics.averageDriveActivation,
                    trainedAverageDriveActivationByIndex: result.trained?.diagnostics.averageDriveActivationByIndex,
                    teacherAverageDriveActivationByIndex: result.teacher.diagnostics.averageDriveActivationByIndex,
                    trainedAverageMotorFinalOutputByIndex: result.trained?.diagnostics.averageMotorFinalOutputByIndex,
                    trainedFinalAltitudeZ: result.trained?.diagnostics.finalAltitudeZ,
                    trainedFinalVerticalVelocityZ: result.trained?.diagnostics.finalVerticalVelocityZ,
                    metricsCount: artifacts.training.metrics.count,
                    recoveryRelabelAttempted: result.recoveryRelabelStatus.attempted,
                    recoveryRelabelDatasetPath: result.recoveryRelabelStatus.datasetDirectory?.path,
                    recoveryRelabelEntryCount: result.recoveryRelabelStatus.report?.relabeledEntryCount,
                    recoveryRelabelCutStepCount: result.recoveryRelabelStatus.report?.relabeledCutStepCount,
                    gateReport: gateReport,
                    postRegression: nil
                )
                probeEntries.append(entry)
                print("[harness] probe task=\(task.rawValue) attempt=\(attempt) terminal=\(entry.terminalState) trainingCheckpoint=\(entry.trainingCheckpoint) probeCheckpoint=\(entry.probeCheckpoint) selected=\(entry.selectedCheckpointRole) repairSource=\(entry.repairSourceCheckpointPath ?? "n/a") recoveryDatasets=\(recoveryDatasetURLs.count) reload=\(entry.reloadSucceeded) harnessSatisfied=\(entry.harnessSatisfied) taskSolved=\(entry.taskSolved)")
                if accepted {
                    taskAccepted = true
                    break
                }
            }
            if !taskAccepted {
                let summary = CheckTrainingHarnessSummary(
                    artifactRoot: artifactRoot.path,
                    environmentReady: true,
                    probes: probeEntries,
                    selectedCandidate: selectedHarnessCandidate(from: probeEntries),
                    allPassed: false
                )
                try writeHarnessSummary(summary, to: artifactRoot)
                print("[harness] artifacts path=\(artifactRoot.path)")
                throw ExitCode.failure
            }
        }

        let summary = CheckTrainingHarnessSummary(
            artifactRoot: artifactRoot.path,
            environmentReady: true,
            probes: probeEntries,
            selectedCandidate: selectedHarnessCandidate(from: probeEntries),
            allPassed: true
        )
        try writeHarnessSummary(summary, to: artifactRoot)
        print("[harness] artifacts path=\(artifactRoot.path)")
        print("[harness] allPassed=true")
    }

    private func writeHarnessSummary(_ summary: CheckTrainingHarnessSummary, to artifactRoot: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(summary).write(
            to: artifactRoot.appendingPathComponent("training-harness-summary.json"),
            options: [.atomic]
        )
    }
}

struct CheckTrainingHarnessSweep: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check-training-harness-sweep",
        abstract: "Run the ManasMLX training harness across multiple MLX seeds and summarize stability."
    )

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(name: .customLong("artifact-root"), help: "Directory where sweep artifacts are written.")
    var artifactRootPath: String?

    @Option(name: .customLong("source-checkpoint"), help: "Optional source checkpoint directory to continue probe attempts from.")
    var sourceCheckpointPath: String?

    @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
    var sequenceLength: Int = 16

    @Option(name: .customLong("epochs"), help: "Epochs for each supervised ManasMLX probe.")
    var epochs: Int = 40

    @Option(name: .customLong("lr"), help: "Learning rate for each supervised ManasMLX probe.")
    var learningRate: Double = 0.001

    @Option(name: .customLong("max-batches"), help: "Maximum training batches for each supervised ManasMLX probe.")
    var maxBatches: Int = 64

    @Option(help: "Number of seed bases to evaluate.")
    var seeds: Int = 5

    @Option(help: "Comma-separated task list: lift,singleLift. Defaults to singleLift.")
    var tasks: String = "singleLift"

    @Option(help: "Maximum probe attempts per seed. Each attempt increments the seed.")
    var attempts: Int = 3

    @Option(name: .customLong("recovery-repeat"), help: "Repeat recovery relabel datasets this many times when mixing retry training data.")
    var recoveryRepeat: Int = 1

    @Option(name: .customLong("mlx-seed"), help: "Base MLX random seed for the sweep.")
    var mlxSeed: UInt64 = 10_000

    @Option(name: .customLong("min-success-rate"), help: "Minimum acceptable success rate in the range 0...1.")
    var minSuccessRate: Double = 1.0

    @Option(help: "kp gain for baseline controller.")
    var kp: Double = 2.0

    @Option(help: "kd gain for baseline controller.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Flag(name: .customLong("require-task-solved"), help: "Require each successful seed to satisfy the full task suite, not only the harness smoke gate.")
    var requireTaskSolved: Bool = false

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
    var noQualityGate: Bool = false

    @Flag(name: .customLong("post-regression"), help: "Run M2 rollout regression against each accepted checkpoint.")
    var postRegression: Bool = false

    @Option(name: .customLong("post-regression-suites"), help: "Comma-separated M2 suite list for post-training checkpoint regression: 6,7,8.")
    var postRegressionSuites: String = "6,7,8"

    @Option(name: .customLong("post-regression-episodes"), help: "Episodes per M2 suite during post-training checkpoint regression.")
    var postRegressionEpisodes: Int = 1

    @Flag(name: .customLong("post-regression-fail-on-truncation"), help: "Treat post-regression max-step truncation as a failure.")
    var postRegressionFailOnTruncation: Bool = false

    @Option(name: .customLong("post-regression-min-reward-average"), help: "Override the task default minimum reward average required for every post-regression rollout track.")
    var postRegressionMinRewardAverage: Double?

    @MainActor
    mutating func run() async throws {
        guard sequenceLength > 0 else {
            throw ValidationError("--sequence must be greater than 0.")
        }
        guard epochs > 0 else {
            throw ValidationError("--epochs must be greater than 0.")
        }
        guard maxBatches > 0 else {
            throw ValidationError("--max-batches must be greater than 0.")
        }
        guard seeds > 0 else {
            throw ValidationError("--seeds must be greater than 0.")
        }
        guard attempts > 0 else {
            throw ValidationError("--attempts must be greater than 0.")
        }
        guard recoveryRepeat > 0 else {
            throw ValidationError("--recovery-repeat must be greater than 0.")
        }
        guard minSuccessRate >= 0 && minSuccessRate <= 1 else {
            throw ValidationError("--min-success-rate must be in the range 0...1.")
        }
        guard postRegressionEpisodes > 0 else {
            throw ValidationError("--post-regression-episodes must be greater than 0.")
        }
        if let postRegressionMinRewardAverage, !postRegressionMinRewardAverage.isFinite {
            throw ValidationError("--post-regression-min-reward-average must be finite when specified.")
        }

        let artifactRoot: URL
        if let artifactRootPath, !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        } else {
            artifactRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-training-harness-sweep-\(UUID().uuidString)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)

        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let parameters = try loadParameters(modelPath: model)
        let embodiment = try loadEmbodiment(modelPath: model)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )

        let environmentRoot = artifactRoot.appendingPathComponent("environment-readiness", isDirectory: true)
        let selectedTasks = try parseProbeTasks(tasks)
        let selectedPostRegressionSuites = try parseRegressionSuites(postRegressionSuites)
        let selectedTaskModes = selectedTasks.map(simulationTaskMode(from:))
        let unsupportedTasks = selectedTasks.filter { $0 == .attitude }
        if !unsupportedTasks.isEmpty {
            throw ValidationError("check-training-harness-sweep supports lift and singleLift. Attitude requires the rollout/regression path until ManasMLX multi-drive probe training is stabilized.")
        }

        let environmentReport = try await ReferenceQuadrotorEnvironmentReadinessChecker().check(
            tasks: selectedTaskModes,
            controller: .teacherActiveAltitudeHold,
            parameters: parameters,
            schedule: schedule,
            determinism: determinism,
            gains: gains,
            robotManifestPath: model,
            embodiment: embodiment,
            artifactRoot: environmentRoot
        )
        for task in environmentReport.tasks {
            print("[harness-sweep] env task=\(task.task) ready=\(task.ready) score=\(String(format: "%.3f", task.score)) dataset=\(task.datasetScenarioCount)/\(task.scenarioCount)")
        }

        guard environmentReport.allReady else {
            let summary = CheckTrainingHarnessSweepSummary(
                artifactRoot: artifactRoot.path,
                startedAt: Date(),
                environmentReady: false,
                requirement: requirementName,
                tasks: selectedTasks.map(\.rawValue),
                seedCount: seeds,
                attemptsPerSeed: attempts,
                successCount: 0,
                successRate: 0,
                minSuccessRate: minSuccessRate,
                allPassed: false,
                seeds: []
            )
            try writeSweepSummary(summary, to: artifactRoot)
            print("[harness-sweep] artifacts path=\(artifactRoot.path)")
            throw ExitCode.failure
        }

        var seedEntries: [CheckTrainingHarnessSeedEntry] = []
        let initialSourceCheckpointURL = sourceCheckpointURL(from: sourceCheckpointPath)
        let harnessGateService = ReferenceQuadrotorTrainingHarnessGateService()
        for seedIndex in 0..<seeds {
            let seedBase = mlxSeed + UInt64(seedIndex * attempts * max(selectedTasks.count, 1))
            var probeEntries: [CheckTrainingHarnessProbeEntry] = []
            var acceptedTasks: [String: Int] = [:]

            for (taskIndex, task) in selectedTasks.enumerated() {
                var currentSourceCheckpointURL = initialSourceCheckpointURL
                var recoveryDatasetURLs: [URL] = []
                for attempt in 1...attempts {
                    let attemptSeed = seedBase + UInt64(taskIndex * attempts + attempt - 1)
                    let attemptRoot = artifactRoot
                        .appendingPathComponent("seed-\(seedBase)", isDirectory: true)
                        .appendingPathComponent(task.rawValue, isDirectory: true)
                        .appendingPathComponent("attempt-\(attempt)", isDirectory: true)
                    let result = try await runCLIManasProbe(
                        task: task,
                        tier: tier,
                        cutPeriodSteps: cutPeriodSteps,
                        model: model,
                        sourceCheckpointURL: currentSourceCheckpointURL,
                        artifactRoot: attemptRoot,
                        iterations: 1,
                        sequenceLength: sequenceLength,
                        epochs: epochs,
                        learningRate: learningRate,
                        maxBatches: maxBatches,
                        workers: 1,
                        minDelta: 0,
                        kp: kp,
                        kd: kd,
                        yawDamping: yawDamping,
                        hoverScale: hoverScale,
                        useAux: false,
                        useQualityGating: !noQualityGate,
                        mlxSeed: attemptSeed,
                        additionalDatasetURLs: recoveryDatasetURLs,
                        additionalDatasetRepeatCount: recoveryRepeat,
                        printEvents: false
                    )
                    let repairSourceCheckpointURL = harnessGateService.repairSourceCheckpointURL(result: result)
                    currentSourceCheckpointURL = repairSourceCheckpointURL
                    if let recoveryDatasetURL = harnessGateService.acceptedRecoveryDatasetURL(result: result) {
                        recoveryDatasetURLs.append(recoveryDatasetURL)
                    }
                    let artifacts = try GeneratedTrainingArtifactCompatibilityVerifier().loadProbeArtifacts(from: attemptRoot)
                    let taskSolved = harnessGateService.taskSolved(result: result)
                    let harnessSatisfied = harnessGateService.satisfied(result: result)
                    let preRegressionGateReport = harnessGateService.report(
                        result: result,
                        requireTaskSolved: requireTaskSolved,
                        postRegression: nil
                    )
                    let accepted = preRegressionGateReport.accepted
                    let postRegressionEntry: ReferenceQuadrotorPostTrainingRegressionEntry?
                    if accepted, postRegression {
                        let checkpointURL = selectedCandidateCheckpointURL(result.comparison)
                        if let checkpointURL {
                            let regressionRoot = attemptRoot.appendingPathComponent("post-regression", isDirectory: true)
                            _ = try await runKuyuRegression(
                                controller: .manasMLX,
                                snapshotURL: checkpointURL,
                                tier: tier,
                                cutPeriodSteps: cutPeriodSteps,
                                tasks: [simulationTaskMode(from: task)],
                                suites: selectedPostRegressionSuites,
                                episodes: postRegressionEpisodes,
                                workers: 1,
                                maxSteps: nil,
                                maxWallTime: nil,
                                model: model,
                                artifactRoot: regressionRoot,
                                kp: kp,
                                kd: kd,
                                yawDamping: yawDamping,
                                hoverScale: hoverScale,
                                failOnTruncation: postRegressionFailOnTruncation,
                                minimumRewardAverage: postRegressionMinRewardAverage,
                                useQualityGating: !noQualityGate
                            )
                            let validatedRegression = try ReferenceQuadrotorRegressionArtifactLoader()
                                .loadSummary(from: regressionRoot)
                            postRegressionEntry = harnessGateService.postRegressionEntry(
                                regression: validatedRegression,
                                artifactPath: regressionRoot.path,
                                minimumRewardAverage: validatedRegression.gateReport.minimumRewardAverage
                            )
                            print("[harness-sweep] seed=\(seedBase) task=\(task.rawValue) attempt=\(attempt) postRegression=\(validatedRegression.allPassed)")
                        } else {
                            postRegressionEntry = try harnessGateService.missingCheckpointPostRegressionEntry(
                                task: task.rawValue,
                                minimumRewardAverageOverride: postRegressionMinRewardAverage
                            )
                        }
                    } else {
                        postRegressionEntry = nil
                    }
                    let gateReport = harnessGateService.report(
                        result: result,
                        requireTaskSolved: requireTaskSolved,
                        postRegression: postRegressionEntry
                    )
                    let entry = CheckTrainingHarnessProbeEntry(
                        task: task.rawValue,
                        attempt: attempt,
                        artifactPath: attemptRoot.path,
                        terminalState: result.manifest.terminalState.rawValue,
                        trainingCheckpoint: result.comparison.checkpointDecision.rawValue,
                        probeCheckpoint: result.probeCheckpointDecision.state.rawValue,
                        selectedCheckpointRole: result.comparison.selectedCheckpointRole.rawValue,
                        selectedCheckpointPath: result.comparison.selectedCheckpointURL?.path,
                        repairSourceCheckpointPath: repairSourceCheckpointURL?.path,
                        reloadSucceeded: result.comparison.reloadSucceeded,
                        teacherScore: result.comparison.teacherScore,
                        initialScore: result.comparison.initialScore,
                        trainedScore: result.comparison.trainedScore,
                        scoreDelta: result.comparison.scoreDelta,
                        policySatisfied: result.comparison.policySatisfied,
                        harnessSatisfied: harnessSatisfied,
                        taskSolved: taskSolved,
                        trainedFailureReasons: result.trained?.diagnostics.failureReasons ?? [],
                        trainedAverageDriveActivation: result.trained?.diagnostics.averageDriveActivation,
                        teacherAverageDriveActivation: result.teacher.diagnostics.averageDriveActivation,
                        trainedAverageDriveActivationByIndex: result.trained?.diagnostics.averageDriveActivationByIndex,
                        teacherAverageDriveActivationByIndex: result.teacher.diagnostics.averageDriveActivationByIndex,
                        trainedAverageMotorFinalOutputByIndex: result.trained?.diagnostics.averageMotorFinalOutputByIndex,
                        trainedFinalAltitudeZ: result.trained?.diagnostics.finalAltitudeZ,
                        trainedFinalVerticalVelocityZ: result.trained?.diagnostics.finalVerticalVelocityZ,
                        metricsCount: artifacts.training.metrics.count,
                        recoveryRelabelAttempted: result.recoveryRelabelStatus.attempted,
                        recoveryRelabelDatasetPath: result.recoveryRelabelStatus.datasetDirectory?.path,
                        recoveryRelabelEntryCount: result.recoveryRelabelStatus.report?.relabeledEntryCount,
                        recoveryRelabelCutStepCount: result.recoveryRelabelStatus.report?.relabeledCutStepCount,
                        gateReport: gateReport,
                        postRegression: postRegressionEntry
                    )
                    probeEntries.append(entry)
                    print("[harness-sweep] seed=\(seedBase) task=\(task.rawValue) attempt=\(attempt) mlxSeed=\(attemptSeed) selected=\(entry.selectedCheckpointRole) repairSource=\(entry.repairSourceCheckpointPath ?? "n/a") recoveryDatasets=\(recoveryDatasetURLs.count) gateAccepted=\(gateReport.accepted) gateReasons=\(gateReport.reasons.joined(separator: "|")) harnessSatisfied=\(harnessSatisfied) taskSolved=\(taskSolved) postRegression=\(postRegressionEntry?.allPassed.description ?? "skipped") scoreDelta=\(formatOptional(result.comparison.scoreDelta))")
                    if gateReport.accepted {
                        acceptedTasks[task.rawValue] = attempt
                        break
                    }
                }
            }

            let successful = selectedTasks.allSatisfy { acceptedTasks[$0.rawValue] != nil }
            let lastProbe = probeEntries.last
            seedEntries.append(
                CheckTrainingHarnessSeedEntry(
                    seedBase: seedBase,
                    successful: successful,
                    acceptedAttempts: acceptedTasks,
                    finalScoreDelta: lastProbe?.scoreDelta,
                    finalTrainedScore: lastProbe?.trainedScore,
                    finalFailureReasons: lastProbe?.trainedFailureReasons ?? [],
                    probes: probeEntries
                )
            )
        }

        let successCount = seedEntries.filter(\.successful).count
        let successRate = Double(successCount) / Double(seeds)
        let allPassed = successRate >= minSuccessRate
        let summary = CheckTrainingHarnessSweepSummary(
            artifactRoot: artifactRoot.path,
            startedAt: Date(),
            environmentReady: true,
            requirement: requirementName,
            tasks: selectedTasks.map(\.rawValue),
            seedCount: seeds,
            attemptsPerSeed: attempts,
            successCount: successCount,
            successRate: successRate,
            minSuccessRate: minSuccessRate,
            allPassed: allPassed,
            seeds: seedEntries
        )
        try writeSweepSummary(summary, to: artifactRoot)
        print("[harness-sweep] artifacts path=\(artifactRoot.path)")
        print("[harness-sweep] successCount=\(successCount)/\(seeds) successRate=\(String(format: "%.3f", successRate)) requirement=\(requirementName) allPassed=\(allPassed)")
        if !allPassed {
            throw ExitCode.failure
        }
    }

    private var requirementName: String {
        requireTaskSolved ? "taskSolved" : "harnessSatisfied"
    }

    private func writeSweepSummary(_ summary: CheckTrainingHarnessSweepSummary, to artifactRoot: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(summary).write(
            to: artifactRoot.appendingPathComponent("training-harness-sweep-summary.json"),
            options: [.atomic]
        )
    }

    private func formatOptional(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.3f", value)
    }
}

struct CheckKuyuRegression: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check-kuyu-regression",
        abstract: "Run Kuyu environment and M2 rollout regression checks."
    )

    @Option(help: "Controller to validate: activeAltitudeHold, sensorBaseline, or manasMLX.")
    var controller: ControllerChoice = .activeAltitudeHold

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Comma-separated environment task list: attitude,lift,singleLift.")
    var tasks: String = "attitude,lift,singleLift"

    @Option(help: "Comma-separated M2 suite list: 6,7,8.")
    var suites: String = "6,7,8"

    @Option(help: "Episodes per M2 suite track.")
    var episodes: Int = 1

    @Option(help: "Worker count for rollout regression.")
    var workers: Int = 1

    @Option(name: .customLong("max-steps"), help: "Maximum steps per M2 rollout episode. Omit for full scenario duration.")
    var maxSteps: Int?

    @Option(name: .customLong("max-wall-time"), help: "Maximum wall-clock seconds per M2 rollout episode. Omit for no wall-time limit.")
    var maxWallTime: Double?

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(help: "ManasMLX model snapshot directory containing model.json/core.safetensors/reflex.safetensors.")
    var snapshot: String = ""

    @Option(name: .customLong("artifact-root"), help: "Directory where regression artifacts are written.")
    var artifactRootPath: String?

    @Option(help: "kp gain for baseline controller.")
    var kp: Double = 2.0

    @Option(help: "kd gain for baseline controller.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Flag(name: .customLong("fail-on-truncation"), help: "Treat max-step truncation as a regression failure.")
    var failOnTruncation: Bool = false

    @Option(name: .customLong("min-reward-average"), help: "Override the task default minimum reward average required for every rollout track.")
    var minimumRewardAverage: Double?

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for ManasMLX rollout.")
    var noQualityGate: Bool = false

    @MainActor
    mutating func run() async throws {
        let selectedController = controllerSelection(from: controller)
        guard episodes > 0 else {
            throw ValidationError("--episodes must be greater than 0.")
        }
        guard workers > 0 else {
            throw ValidationError("--workers must be greater than 0.")
        }
        if let maxSteps, maxSteps <= 0 {
            throw ValidationError("--max-steps must be greater than 0 when specified.")
        }
        if let maxWallTime, !(maxWallTime.isFinite && maxWallTime > 0) {
            throw ValidationError("--max-wall-time must be greater than 0 when specified.")
        }
        if let minimumRewardAverage, !minimumRewardAverage.isFinite {
            throw ValidationError("--min-reward-average must be finite when specified.")
        }

        let selectedTasks = try parseProbeTasks(tasks).map(simulationTaskMode(from:))
        let selectedSuites = try parseRegressionSuites(suites)
        let artifactRoot: URL
        if let artifactRootPath, !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        } else {
            artifactRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-regression-\(UUID().uuidString)", isDirectory: true)
        }
        let snapshotURL = try regressionSnapshotURL(snapshot, controller: selectedController)
        _ = try await runKuyuRegression(
            controller: selectedController,
            snapshotURL: snapshotURL,
            tier: tier,
            cutPeriodSteps: cutPeriodSteps,
            tasks: selectedTasks,
            suites: selectedSuites,
            episodes: episodes,
            workers: workers,
            maxSteps: maxSteps,
            maxWallTime: maxWallTime,
            model: model,
            artifactRoot: artifactRoot,
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverScale: hoverScale,
            failOnTruncation: failOnTruncation,
            minimumRewardAverage: minimumRewardAverage,
            useQualityGating: !noQualityGate
        )
        let validatedSummary = try ReferenceQuadrotorRegressionArtifactLoader().loadSummary(from: artifactRoot)
        print("[regression] artifacts path=\(artifactRoot.path)")
        print("[regression] environmentReady=\(validatedSummary.environmentReady) rolloutPassed=\(validatedSummary.rolloutPassed) gateAccepted=\(validatedSummary.gateReport.accepted) reasons=\(validatedSummary.gateReport.reasons.joined(separator: "|")) allPassed=\(validatedSummary.allPassed)")
        if !validatedSummary.allPassed {
            throw ExitCode.failure
        }
    }

    private func parseRegressionSuites(_ raw: String) throws -> [Int] {
        let values = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else {
            throw ValidationError("--suites must include at least one suite.")
        }
        var seenSuites = Set<Int>()
        return try values.map { value in
            guard let suite = Int(value), (0...8).contains(suite) else {
                throw ValidationError("--suites supports 0–8 (attitude 0–5 = A1 conformance suites, 6–8 = long-horizon tracks).")
            }
            guard seenSuites.insert(suite).inserted else {
                throw ValidationError("--suites contains a duplicate suite: \(suite)")
            }
            return suite
        }
    }

}

struct CheckKuyuRegressionMatrix: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check-kuyu-regression-matrix",
        abstract: "Run a task/controller matrix of Kuyu regression checks."
    )

    @Option(help: "Comma-separated controller list: activeAltitudeHold,sensorBaseline,manasMLX.")
    var controllers: String = "activeAltitudeHold"

    @Option(help: "Comma-separated task list: lift,singleLift.")
    var tasks: String = "lift,singleLift"

    @Option(help: "Comma-separated M2 suite list: 6,7,8.")
    var suites: String = "6"

    @Option(help: "Episodes per matrix cell.")
    var episodes: Int = 1

    @Option(help: "Worker count for rollout regression.")
    var workers: Int = 1

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(help: "ManasMLX model snapshot directory.")
    var snapshot: String = ""

    @Option(name: .customLong("artifact-root"), help: "Directory where matrix artifacts are written.")
    var artifactRootPath: String?

    @Option(name: .customLong("min-reward-average"), help: "Override task default minimum reward average.")
    var minimumRewardAverage: Double?

    @Flag(name: .customLong("fail-on-truncation"), help: "Treat max-step truncation as a regression failure.")
    var failOnTruncation: Bool = false

    @MainActor
    mutating func run() async throws {
        guard episodes > 0 else {
            throw ValidationError("--episodes must be greater than 0.")
        }
        guard workers > 0 else {
            throw ValidationError("--workers must be greater than 0.")
        }
        if let minimumRewardAverage, !minimumRewardAverage.isFinite {
            throw ValidationError("--min-reward-average must be finite when specified.")
        }

        let selectedControllers = try parseRegressionControllers(controllers)
        let selectedTasks = try parseProbeTasks(tasks).map(simulationTaskMode(from:))
        let selectedSuites = try parseRegressionSuites(suites)
        let artifactRoot: URL
        if let artifactRootPath, !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        } else {
            artifactRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-regression-matrix-\(UUID().uuidString)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)

        var entries: [KuyuRegressionMatrixEntry] = []
        for controller in selectedControllers {
            let selectedController = controllerSelection(from: controller)
            for task in selectedTasks {
                let taskName = rolloutTaskChoice(from: task).rawValue
                let cellRoot = artifactRoot
                    .appendingPathComponent(controller.rawValue, isDirectory: true)
                    .appendingPathComponent(taskName, isDirectory: true)
                do {
                    let snapshotURL = try regressionSnapshotURL(snapshot, controller: selectedController)
                    _ = try await runKuyuRegression(
                        controller: selectedController,
                        snapshotURL: snapshotURL,
                        tier: tier,
                        cutPeriodSteps: cutPeriodSteps,
                        tasks: [task],
                        suites: selectedSuites,
                        episodes: episodes,
                        workers: workers,
                        maxSteps: nil,
                        maxWallTime: nil,
                        model: model,
                        artifactRoot: cellRoot,
                        kp: 2.0,
                        kd: 0.25,
                        yawDamping: 0.2,
                        hoverScale: 1.0,
                        failOnTruncation: failOnTruncation,
                        minimumRewardAverage: minimumRewardAverage,
                        useQualityGating: true
                    )
                    let summary = try ReferenceQuadrotorRegressionArtifactLoader().loadSummary(from: cellRoot)
                    entries.append(KuyuRegressionMatrixEntry(
                        controller: controller.rawValue,
                        task: taskName,
                        artifactPath: cellRoot.path,
                        accepted: summary.gateReport.accepted,
                        reasons: summary.gateReport.reasons
                    ))
                    print("[regression-matrix] controller=\(controller.rawValue) task=\(taskName) accepted=\(summary.gateReport.accepted) artifact=\(cellRoot.path)")
                } catch {
                    entries.append(KuyuRegressionMatrixEntry(
                        controller: controller.rawValue,
                        task: taskName,
                        artifactPath: cellRoot.path,
                        accepted: false,
                        reasons: [String(describing: error)]
                    ))
                    print("[regression-matrix] controller=\(controller.rawValue) task=\(taskName) accepted=false reason=\(error)")
                }
            }
        }

        let summary = KuyuRegressionMatrixSummary(
            artifactRoot: artifactRoot.path,
            controllers: selectedControllers.map(\.rawValue),
            tasks: selectedTasks.map { rolloutTaskChoice(from: $0).rawValue },
            suites: selectedSuites,
            episodes: episodes,
            allPassed: entries.allSatisfy(\.accepted),
            entries: entries
        )
        try writeRegressionMatrixSummary(summary, to: artifactRoot)
        print("[regression-matrix] artifacts path=\(artifactRoot.path) allPassed=\(summary.allPassed)")
        if !summary.allPassed {
            throw ExitCode.failure
        }
    }
}

private struct KuyuRegressionMatrixSummary: Codable {
    let artifactRoot: String
    let controllers: [String]
    let tasks: [String]
    let suites: [Int]
    let episodes: Int
    let allPassed: Bool
    let entries: [KuyuRegressionMatrixEntry]
}

private struct KuyuRegressionMatrixEntry: Codable {
    let controller: String
    let task: String
    let artifactPath: String
    let accepted: Bool
    let reasons: [String]
}

private func writeRegressionMatrixSummary(_ summary: KuyuRegressionMatrixSummary, to artifactRoot: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(summary).write(
        to: artifactRoot.appendingPathComponent("kuyu-regression-matrix-summary.json"),
        options: [.atomic]
    )
}

private func runKuyuRegression(
    controller selectedController: ControllerSelection,
    snapshotURL: URL?,
    tier: TierChoice,
    cutPeriodSteps: UInt64,
    tasks selectedTasks: [SimulationTaskMode],
    suites selectedSuites: [Int],
    episodes: Int,
    workers: Int,
    maxSteps: Int?,
    maxWallTime: Double?,
    model: String,
    artifactRoot: URL,
    kp: Double,
    kd: Double,
    yawDamping: Double,
    hoverScale: Double,
    failOnTruncation: Bool,
    minimumRewardAverage: Double?,
    useQualityGating: Bool
) async throws -> ReferenceQuadrotorRegressionSummary {
    let rolloutTask = regressionRolloutTask(selectedTasks)
    let environmentTasks = selectedTasks.map { task in
        learningCampaignRolloutTask(from: rolloutTaskChoice(from: task))
    }
    let summary = try await ReferenceQuadrotorRegressionRunner().run(
        config: ReferenceQuadrotorRegressionRunConfig(
            controller: selectedController,
            snapshotURL: snapshotURL,
            tier: learningCampaignTier(from: tier),
            cutPeriodSteps: cutPeriodSteps,
            task: learningCampaignRolloutTask(from: rolloutTask),
            environmentTasks: environmentTasks,
            suites: selectedSuites,
            episodes: episodes,
            workers: workers,
            maxSteps: maxSteps,
            maxWallTime: maxWallTime,
            robotManifestPath: model,
            artifactRoot: artifactRoot,
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverScale: hoverScale,
            failOnTruncation: failOnTruncation,
            minimumRewardAverage: minimumRewardAverage,
            useQualityGating: useQualityGating
        )
    )
    for entry in summary.rolloutSuites {
        if entry.episodeCount == 0, !entry.failureReasons.isEmpty {
            print("[regression] suite=\(entry.suite) track=\(entry.track) failed reason=\(entry.failureReasons.joined(separator: " | "))")
        } else {
            print("[regression] suite=\(entry.suite) track=\(entry.track) episodes=\(entry.episodeCount) workers=\(entry.workerSummaries.count) rewardAvg=\(String(format: "%.3f", entry.rewardAverage)) failures=\(entry.failureCount) taskFailures=\(entry.taskFailureCount) taskPassRate=\(String(format: "%.3f", regressionTaskPassRate(entry))) truncated=\(entry.truncatedCount) \(regressionQualityText(entry.taskQuality)) \(regressionWorkerText(entry.workerSummaries))")
        }
    }
    return summary
}

private func regressionSnapshotURL(_ raw: String, controller: ControllerSelection) throws -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard controller == .manasMLX else {
        return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed, isDirectory: true)
    }
    guard !trimmed.isEmpty else {
        throw ValidationError("--snapshot is required when --controller manasMLX.")
    }
    return URL(fileURLWithPath: trimmed, isDirectory: true)
}

private func parseRegressionSuites(_ raw: String) throws -> [Int] {
    let values = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !values.isEmpty else {
        throw ValidationError("--suites must include at least one suite.")
    }
    var seenSuites = Set<Int>()
    return try values.map { value in
        guard let suite = Int(value), (0...8).contains(suite) else {
            throw ValidationError("--suites supports 0–8 (attitude 0–5 = A1 conformance suites, 6–8 = long-horizon tracks).")
        }
        guard seenSuites.insert(suite).inserted else {
            throw ValidationError("--suites contains a duplicate suite: \(suite)")
        }
        return suite
    }
}

private func regressionTaskPassRate(_ entry: ReferenceQuadrotorRegressionRolloutEntry) -> Double {
    guard entry.episodeCount > 0 else { return 0 }
    return Double(entry.taskPassCount) / Double(entry.episodeCount)
}

private func regressionQualityText(_ summaries: [ReferenceQuadrotorTaskQualitySummary]) -> String {
    guard let summary = summaries.first else {
        return "qualityGateTask=missing"
    }
    let hold = formattedRatio(
        achieved: summary.achievedHoldTime,
        required: summary.requiredHoldTime
    )
    let altitudeError = summary.maxAltitudeErrorAfterWarmup.map { String(format: "%.3f", $0) } ?? "--"
    let tolerance = summary.tolerance.map { String(format: "%.3f", $0) } ?? "--"
    return "qualityGateTask=\(summary.task) achievedHoldTime=\(hold.achieved) requiredHoldTime=\(hold.required) maxAltitudeErrorAfterWarmup=\(altitudeError) tolerance=\(tolerance)"
}

private func regressionWorkerText(_ summaries: [ReferenceQuadrotorRegressionWorkerSummary]) -> String {
    guard let slowest = summaries.min(by: { lhs, rhs in lhs.throughput < rhs.throughput }) else {
        return "workerThroughput=missing"
    }
    return "workerThroughputMin=\(String(format: "%.3f", slowest.throughput))"
}

private func formattedRatio(achieved: Double?, required: Double?) -> (achieved: String, required: String) {
    let achievedText = achieved.map { String(format: "%.3f", $0) } ?? "--"
    let requiredText = required.map { String(format: "%.3f", $0) } ?? "--"
    return (achievedText, requiredText)
}

private func regressionRolloutTask(_ selectedTasks: [SimulationTaskMode]) -> RolloutTaskChoice {
    guard selectedTasks.count == 1, let task = selectedTasks.first else {
        return .attitude
    }
    return rolloutTaskChoice(from: task)
}

private func rolloutTaskChoice(from task: SimulationTaskMode) -> RolloutTaskChoice {
    switch task {
    case .attitude:
        return .attitude
    case .lift:
        return .lift
    case .singleLift:
        return .singleLift
    }
}

private func selectedCandidateCheckpointURL(_ comparison: TrainingProbeComparison) -> URL? {
    guard comparison.selectedCheckpointRole == .candidate else {
        return nil
    }
    return comparison.selectedCheckpointURL
}

private func selectedHarnessCandidate(from entries: [CheckTrainingHarnessProbeEntry]) -> CheckTrainingHarnessSelectedCandidate? {
    for entry in entries.reversed() where entry.gateReport.accepted && entry.selectedCheckpointRole == "candidate" {
        guard let checkpointPath = entry.selectedCheckpointPath else {
            continue
        }
        return CheckTrainingHarnessSelectedCandidate(
            task: entry.task,
            attempt: entry.attempt,
            checkpoint: checkpointPath,
            artifactPath: entry.artifactPath,
            score: entry.trainedScore,
            scoreDelta: entry.scoreDelta
        )
    }
    return nil
}

private func sourceCheckpointURL(from rawPath: String?) -> URL? {
    guard let rawPath else {
        return nil
    }
    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }
    return URL(fileURLWithPath: trimmed, isDirectory: true)
}

private struct CheckTrainingHarnessSummary: Codable {
    let artifactRoot: String
    let environmentReady: Bool
    let probes: [CheckTrainingHarnessProbeEntry]
    let selectedCandidate: CheckTrainingHarnessSelectedCandidate?
    let allPassed: Bool
}

private struct CheckTrainingHarnessSelectedCandidate: Codable {
    let task: String
    let attempt: Int
    let checkpoint: String
    let artifactPath: String
    let score: Double?
    let scoreDelta: Double?
}

private struct CheckTrainingHarnessSweepSummary: Codable {
    let artifactRoot: String
    let startedAt: Date
    let environmentReady: Bool
    let requirement: String
    let tasks: [String]
    let seedCount: Int
    let attemptsPerSeed: Int
    let successCount: Int
    let successRate: Double
    let minSuccessRate: Double
    let allPassed: Bool
    let seeds: [CheckTrainingHarnessSeedEntry]
}

private struct CheckTrainingHarnessSeedEntry: Codable {
    let seedBase: UInt64
    let successful: Bool
    let acceptedAttempts: [String: Int]
    let finalScoreDelta: Double?
    let finalTrainedScore: Double?
    let finalFailureReasons: [String]
    let probes: [CheckTrainingHarnessProbeEntry]
}

private struct CheckTrainingHarnessProbeEntry: Codable {
    let task: String
    let attempt: Int
    let artifactPath: String
    let terminalState: String
    let trainingCheckpoint: String
    let probeCheckpoint: String
    let selectedCheckpointRole: String
    let selectedCheckpointPath: String?
    let repairSourceCheckpointPath: String?
    let reloadSucceeded: Bool
    let teacherScore: Double
    let initialScore: Double
    let trainedScore: Double?
    let scoreDelta: Double?
    let policySatisfied: Bool
    let harnessSatisfied: Bool
    let taskSolved: Bool
    let trainedFailureReasons: [String]
    let trainedAverageDriveActivation: Double?
    let teacherAverageDriveActivation: Double?
    let trainedAverageDriveActivationByIndex: [Double]?
    let teacherAverageDriveActivationByIndex: [Double]?
    let trainedAverageMotorFinalOutputByIndex: [Double]?
    let trainedFinalAltitudeZ: Double?
    let trainedFinalVerticalVelocityZ: Double?
    let metricsCount: Int
    let recoveryRelabelAttempted: Bool
    let recoveryRelabelDatasetPath: String?
    let recoveryRelabelEntryCount: Int?
    let recoveryRelabelCutStepCount: Int?
    let gateReport: TrainingHarnessGateReport
    let postRegression: ReferenceQuadrotorPostTrainingRegressionEntry?
}

@MainActor
private func runCLIManasProbe(
    task: RolloutTaskChoice,
    tier: TierChoice,
    cutPeriodSteps: UInt64,
    model: String,
    sourceCheckpointURL: URL?,
    artifactRoot: URL,
    iterations: Int,
    sequenceLength: Int,
    epochs: Int,
    learningRate: Double,
    maxBatches: Int?,
    workers: Int,
    minDelta: Double,
    kp: Double,
    kd: Double,
    yawDamping: Double,
    hoverScale: Double,
    useAux: Bool,
    useQualityGating: Bool,
    mlxSeed: UInt64?,
    additionalDatasetURLs: [URL] = [],
    additionalDatasetRepeatCount: Int = 1,
    printEvents: Bool
) async throws -> TrainingProbeResult {
    if let mlxSeed {
        ManasMLXRandomSeed.seed(mlxSeed)
        if printEvents {
            print("[probe] mlxSeed=\(mlxSeed)")
        }
    }
    let preflight = try ManasMLXRuntimeReadinessService().report(
        for: ManasMLXRuntimeReadinessRequest(
            robotManifestPath: model,
            sourceCheckpointURL: sourceCheckpointURL
        )
    )
    if printEvents {
        print("[probe] preflight mlx=\(preflight.mlxRuntimeReady) robotManifestLoaded=\(preflight.robotManifestLoaded) sourceCheckpointLoadable=\(preflight.sourceCheckpointLoadable)")
        if !additionalDatasetURLs.isEmpty {
            print("[probe] additionalDatasets=\(additionalDatasetURLs.map(\.path).joined(separator: ","))")
        }
    }

    let determinism = try makeDeterminism(tier: tier)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
    let parameters = try loadParameters(modelPath: model)
    let embodiment = try loadEmbodiment(modelPath: model)
    let gains = try ImuRateDampingCutGains(
        kp: kp,
        kd: kd,
        yawDamping: yawDamping,
        hoverThrustScale: hoverScale
    )
    let taskMode = simulationTaskMode(from: task)
    let runID = "probe-\(UUID().uuidString)"
    let teacherRequest = SimulationRunRequest(
        controller: .teacherActiveAltitudeHold,
        taskMode: taskMode,
        gains: gains,
        cutPeriodSteps: cutPeriodSteps,
        noise: .zero,
        determinism: determinism,
        robotManifestPath: model,
        overrideParameters: model.isEmpty ? nil : parameters,
        useAux: useAux,
        useQualityGating: useQualityGating
    )
    let trainingRequest = SimulationRunRequest(
        controller: .manasMLX,
        taskMode: taskMode,
        gains: gains,
        cutPeriodSteps: cutPeriodSteps,
        noise: .zero,
        determinism: determinism,
        robotManifestPath: model,
        overrideParameters: model.isEmpty ? nil : parameters,
        useAux: useAux,
        useQualityGating: useQualityGating
    )

    let initialStore = ManasMLXModelStore()
    let workerStore = ManasMLXModelStore()
    let trainedStore = ManasMLXModelStore()
    if let sourceCheckpointURL {
        _ = try initialStore.loadModel(from: sourceCheckpointURL)
    }

    let sourceSnapshot = sourceCheckpointURL.map { url in
        TrainingBackendSnapshot(
            snapshotID: "\(runID)-source",
            checkpointID: url.lastPathComponent,
            checkpointURL: url,
            robotManifestID: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : model,
            configHash: model
        )
    }
    let workerPlan: ParallelTrainingWorkerPlan?
    if let sourceCheckpointURL, workers > 1 {
        workerPlan = try await ParallelTrainingWorkerPlanBuilder().build(
            runID: "\(runID)-training",
            workerCount: workers,
            sourceSnapshot: sourceSnapshot,
            rolloutRoot: artifactRoot
                .appendingPathComponent("training", isDirectory: true)
                .appendingPathComponent("worker-rollouts", isDirectory: true),
            snapshotProvider: ManasMLXSnapshotProvider(
                sourceCheckpointURL: sourceCheckpointURL,
                workerRootURL: artifactRoot
                    .appendingPathComponent("training", isDirectory: true)
                    .appendingPathComponent("worker-snapshots", isDirectory: true),
                policyID: "manasMLX",
                robotManifestID: sourceSnapshot?.robotManifestID,
                configHash: sourceSnapshot?.configHash
            )
        )
        if printEvents {
            print("[probe] workerPlan workers=\(workerPlan?.workerCount ?? workers)")
        }
    } else {
        workerPlan = nil
    }

    let backend = ManasMLXTrainingBackend(
        runtime: ManasMLXTrainingRuntime(modelStore: workerStore),
        saveDirectory: artifactRoot
            .appendingPathComponent("training", isDirectory: true)
            .appendingPathComponent("candidate-checkpoints", isDirectory: true),
        rolloutDatasetLoader: .referenceQuadrotor()
    )
    let probe = TrainingProbeOrchestrator(
        scenarioExecutor: CLITrainingProbeExecutor(
            teacherRequest: teacherRequest,
            initialStore: initialStore,
            trainedStore: trainedStore,
            parameters: parameters,
            schedule: schedule,
            embodiment: embodiment
        ),
        backend: backend
    )
    return await probe.run(
        probeConfig: TrainingProbeConfig(probeID: runID, minScoreDelta: minDelta),
        teacherRequest: teacherRequest,
        trainingRequest: trainingRequest,
        trainingConfig: TrainingRunConfig(
            runID: "\(runID)-training",
            mode: .supervised,
            maxIterations: iterations,
            minDelta: 0.01,
            workerCount: workers,
            enableDatasetExport: true,
            enableTraining: true,
            stopOnPass: false,
            parentCheckpointID: sourceSnapshot?.checkpointID,
            policyID: "manasMLX",
            parallelWorkerPlan: workerPlan
        ),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: artifactRoot,
            additionalDatasetURLs: additionalDatasetURLs,
            additionalDatasetRepeatCount: additionalDatasetRepeatCount,
            sequenceLength: sequenceLength,
            epochs: epochs,
            learningRate: learningRate,
            useAux: useAux,
            useQualityGating: useQualityGating,
            maxBatches: maxBatches,
            sourceSnapshot: sourceSnapshot
        ),
        artifactDirectory: artifactRoot
    ) { event in
        guard printEvents else { return }
        switch event {
        case .iterationStarted(let iteration):
            print("[probe] training iter=\(iteration) started")
        case .suiteCompleted(let iteration, _, let score):
            print("[probe] training iter=\(iteration) teacherDatasetScore=\(String(format: "%.3f", score))")
        case .datasetExported(let iteration, let directory, let count):
            print("[probe] training iter=\(iteration) dataset count=\(count) path=\(directory)")
        case .trainingCompleted(let iteration, let backendResult):
            print("[probe] training iter=\(iteration) loss=\(String(format: "%.6f", backendResult.finalLoss))")
        case .convergenceUpdated(let summary):
            print("[probe] convergence accepted=\(summary.accepted) reason=\(summary.reason)")
        default:
            break
        }
    }
}

private func parseProbeTasks(_ raw: String) throws -> [RolloutTaskChoice] {
    let parts = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !parts.isEmpty else {
        throw ValidationError("--tasks must include at least one task.")
    }
    var tasks: [RolloutTaskChoice] = []
    for part in parts {
        guard let task = RolloutTaskChoice(rawValue: part) else {
            throw ValidationError("Unsupported task '\(part)'. Use attitude, lift, or singleLift.")
        }
        if !tasks.contains(task) {
            tasks.append(task)
        }
    }
    return tasks
}

@MainActor
struct CLIScenarioExecutor: TrainingScenarioExecuting {
    let store: ManasMLXModelStore
    let parameters: ReferenceQuadrotorParameters
    let schedule: SimulationSchedule
    let embodiment: EmbodimentContract?

    func runSuiteForTrainingRun(request: SimulationRunRequest) async throws -> TrainingScenarioRunOutput {
        let output = try await store.runReferenceQuadrotor(
            parameters: parameters,
            schedule: schedule,
            request: request,
            embodiment: embodiment,
            control: nil
        )
        return TrainingScenarioRunOutput(kuyAtt1: output)
    }
}

@MainActor
private final class CLITrainingProbeExecutor: TrainingProbeScenarioExecuting {
    private let teacherRequest: SimulationRunRequest
    private let initialStore: ManasMLXModelStore
    private let trainedStore: ManasMLXModelStore
    private let parameters: ReferenceQuadrotorParameters
    private let schedule: SimulationSchedule
    private let embodiment: EmbodimentContract?

    init(
        teacherRequest: SimulationRunRequest,
        initialStore: ManasMLXModelStore,
        trainedStore: ManasMLXModelStore,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        embodiment: EmbodimentContract?
    ) {
        self.teacherRequest = teacherRequest
        self.initialStore = initialStore
        self.trainedStore = trainedStore
        self.parameters = parameters
        self.schedule = schedule
        self.embodiment = embodiment
    }

    func runProbeSuite(
        stage: TrainingProbeStage,
        request: SimulationRunRequest,
        checkpointURL: URL?
    ) async throws -> TrainingScenarioRunOutput {
        switch stage {
        case .teacherActiveAltitudeHold:
            let output = try await ReferenceQuadrotorScenarioRuntime(modelStore: initialStore).run(
                request: teacherRequest,
                parameters: parameters,
                schedule: schedule,
                embodiment: embodiment,
                control: nil
            )
            return TrainingScenarioRunOutput(kuyAtt1: output)
        case .trainingIteration:
            if teacherRequest.taskMode == .singleLift {
                let output = try await KuyuSingleLiftTeacherDatasetRunner().run(
                    request: teacherRequest,
                    parameters: parameters,
                    schedule: schedule,
                    control: nil
                )
                return TrainingScenarioRunOutput(kuyAtt1: output)
            }
            let output = try await ReferenceQuadrotorScenarioRuntime(modelStore: initialStore).run(
                request: teacherRequest,
                parameters: parameters,
                schedule: schedule,
                embodiment: embodiment,
                control: nil
            )
            return TrainingScenarioRunOutput(kuyAtt1: output)
        case .initialPolicy:
            let output = try await initialStore.runReferenceQuadrotor(
                parameters: parameters,
                schedule: schedule,
                request: request,
                embodiment: embodiment,
                control: nil
            )
            return TrainingScenarioRunOutput(kuyAtt1: output)
        case .trainedPolicy:
            guard let checkpointURL else {
                throw ValidationError("Accepted checkpoint URL is required before trained probe run.")
            }
            _ = try trainedStore.loadModel(from: checkpointURL)
            let output = try await trainedStore.runReferenceQuadrotor(
                parameters: parameters,
                schedule: schedule,
                request: request,
                embodiment: embodiment,
                control: nil
            )
            return TrainingScenarioRunOutput(kuyAtt1: output)
        }
    }

    func writeRecoveryRelabelDataset(
        output: TrainingScenarioRunOutput,
        request: SimulationRunRequest,
        to directory: URL,
        includeSuccessfulScenarios: Bool
    ) async throws -> AttitudeRecoveryRelabelReport? {
        switch request.taskMode {
        case .attitude:
            let definitions = try KuyAtt1Suite().scenarios()
            let relabeler = AttitudeRecoveryRelabeler()
            let result = try relabeler.relabel(
                entries: output.logs,
                definitions: definitions,
                parameters: parameters,
                gains: request.gains,
                config: AttitudeRecoveryRelabelConfig(includeOnlyFailedScenarios: !includeSuccessfulScenarios)
            )
            _ = try relabeler.write(result: result, to: directory)
            return result.report
        case .lift:
            let definitions = try KuyLiftSuite().scenarios()
            let relabeler = LiftRecoveryRelabeler()
            let result = try relabeler.relabel(
                entries: output.logs,
                definitions: definitions,
                parameters: parameters,
                config: LiftRecoveryRelabelConfig(
                    includeOnlyFailedScenarios: !includeSuccessfulScenarios,
                    hoverThrustScale: request.gains.hoverThrustScale
                )
            )
            _ = try relabeler.write(result: result, to: directory)
            return result.report
        case .singleLift:
            let definitions = try KuySingleLiftSuite().scenarios()
            let tunedParameters = try KuyuSingleLiftParameterTuning.tuned(
                parameters: parameters,
                hoverThrustScale: request.gains.hoverThrustScale
            )
            let relabeler = SinglePropRecoveryRelabeler()
            let result = try relabeler.relabel(
                entries: output.logs,
                definitions: definitions,
                parameters: tunedParameters,
                config: SinglePropRecoveryRelabelConfig(
                    includeOnlyFailedScenarios: !includeSuccessfulScenarios,
                    hoverThrustScale: request.gains.hoverThrustScale
                )
            )
            _ = try relabeler.write(result: result, to: directory)
            return result.report
        }
    }
}

struct EvolveManas: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "evolve-manas",
        abstract: "Run a Kuyu-backed evolutionary harness over ManasMLX checkpoint candidates."
    )

    @Option(help: "Task to optimize: lift or singleLift.")
    var task: RolloutTaskChoice = .lift

    @Option(help: "Source ManasMLX model snapshot directory.")
    var snapshot: String

    @Option(help: "Population size per generation.")
    var population: Int = 100

    @Option(help: "Maximum generation budget. Normal completion should come from convergence or gate acceptance.")
    var generations: Int = 1_000

    @Option(name: .customLong("elite-count"), help: "Number of candidates selected as parents.")
    var eliteCount: Int = 10

    @Option(help: "Worker count for rollout regression.")
    var workers: Int = 1

    @Option(name: .customLong("candidate-evaluation-concurrency"), help: "Maximum Manas candidate evaluations to run concurrently.")
    var candidateEvaluationConcurrency: Int = 100

    @Flag(name: .customLong("no-auto-parallelism"), help: "Disable machine-optimized population and evaluation concurrency.")
    var noAutoParallelism: Bool = false

    @Option(help: "Comma-separated M2 suite list: 6,7,8.")
    var suites: String = "6"

    @Option(help: "Episodes per candidate regression.")
    var episodes: Int = 1

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(name: .customLong("artifact-root"), help: "Directory where evolution artifacts are written.")
    var artifactRootPath: String?

    @Option(name: .customLong("mutation-rate"), help: "Mutation rate passed to the ManasMLX variation provider.")
    var mutationRate: Double = 0.14

    @Option(name: .customLong("mutation-noise-scale"), help: "Gaussian mutation noise scale.")
    var mutationNoiseScale: Double = 0.025

    @Option(name: .customLong("search-strategy"), help: "Evolution search strategy: genetic, antitheticEvolutionStrategy, or qualityDiversity.")
    var searchStrategy: EvolutionSearchStrategyChoice = .genetic

    @Option(name: .customLong("bootstrap-source"), help: "Bootstrap source metadata: checkpoint, teacher, demonstration, or none.")
    var bootstrapSource: EvolutionBootstrapSourceChoice = .checkpoint

    @Option(name: .customLong("world-model-usage"), help: "World-model role metadata: disabled, evaluationAssist, or imaginationAssist.")
    var worldModelUsage: EvolutionWorldModelUsageChoice = .disabled

    @Option(name: .customLong("common-random-seed"), help: "Common seed used for ES-style paired perturbations.")
    var commonRandomSeed: UInt64 = 1

    @Flag(name: .customLong("antithetic-sampling"), help: "Use paired positive/negative perturbations with common random seeds.")
    var antitheticSampling: Bool = false

    @Flag(name: .customLong("adaptive-mutation"), inversion: .prefixedNo, help: "Adapt mutation rate and noise scale based on generation gate results.")
    var adaptiveMutation: Bool = true

    @Option(help: "Candidate variation mode: gaussian or copy.")
    var variation: EvolutionVariationChoice = .gaussian

    @Option(help: "Candidate evaluation mode: regression.")
    var evaluation: EvolutionEvaluationChoice = .regression

    @Flag(name: .customLong("no-crossover"), help: "Disable elite checkpoint averaging before mutation.")
    var noCrossover: Bool = false

    @Option(name: .customLong("min-reward-average"), help: "Override task default minimum reward average.")
    var minimumRewardAverage: Double?

    @Option(name: .customLong("min-incumbent-improvement"), help: "Minimum strict scalar-fitness improvement over the incumbent checkpoint.")
    var minimumIncumbentImprovement: Double = 0

    @Option(name: .customLong("min-novelty-score"), help: "Minimum novelty score required for a candidate to enter the evolution archive.")
    var minimumNoveltyScore: Double?

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for ManasMLX rollout.")
    var noQualityGate: Bool = false

    @MainActor
    mutating func run() async throws {
        guard task == .lift || task == .singleLift else {
            throw ValidationError("evolve-manas currently supports lift and singleLift.")
        }
        guard population > 0 else {
            throw ValidationError("--population must be greater than 0.")
        }
        guard generations > 0 else {
            throw ValidationError("--generations must be greater than 0.")
        }
        guard eliteCount > 0, eliteCount <= population else {
            throw ValidationError("--elite-count must be greater than 0 and no larger than --population.")
        }
        guard workers > 0 else {
            throw ValidationError("--workers must be greater than 0.")
        }
        guard candidateEvaluationConcurrency > 0, candidateEvaluationConcurrency <= population else {
            throw ValidationError("--candidate-evaluation-concurrency must be greater than 0 and no larger than --population.")
        }
        guard episodes > 0 else {
            throw ValidationError("--episodes must be greater than 0.")
        }
        guard mutationRate.isFinite, mutationRate >= 0 else {
            throw ValidationError("--mutation-rate must be finite and non-negative.")
        }
        guard mutationNoiseScale.isFinite, mutationNoiseScale >= 0 else {
            throw ValidationError("--mutation-noise-scale must be finite and non-negative.")
        }
        if let minimumRewardAverage, !minimumRewardAverage.isFinite {
            throw ValidationError("--min-reward-average must be finite when specified.")
        }
        guard evaluation == .regression else {
            throw ValidationError("--evaluation candidateOnly is unsupported because evolution artifacts require physical regression evidence.")
        }
        let evolutionProfile = try TaskEvaluationProfile.profile(task: task.rawValue)
        let effectiveMinimumRewardAverage = try ReferenceQuadrotorRegressionQualityGatePolicy.minimumRewardAverage(
            override: minimumRewardAverage,
            task: evolutionProfile.task
        )
        guard minimumIncumbentImprovement.isFinite, minimumIncumbentImprovement >= 0 else {
            throw ValidationError("--min-incumbent-improvement must be finite and non-negative.")
        }
        if let minimumNoveltyScore,
           (!minimumNoveltyScore.isFinite || minimumNoveltyScore < 0) {
            throw ValidationError("--min-novelty-score must be finite and non-negative when specified.")
        }
        let trimmedSnapshot = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSnapshot.isEmpty else {
            throw ValidationError("--snapshot is required.")
        }
        let snapshotURL = URL(fileURLWithPath: trimmedSnapshot, isDirectory: true)
        try checkEvolutionInputs(snapshotURL: snapshotURL)
        let artifactRoot: URL
        if let artifactRootPath, !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        } else {
            artifactRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-evolve-manas-\(UUID().uuidString)", isDirectory: true)
        }
        let selectedSuites = try parseRegressionSuites(suites)
        let effectivePopulation: Int
        let effectiveEliteCount: Int
        let effectiveWorkers: Int
        let effectiveCandidateEvaluationConcurrency: Int
        if !noAutoParallelism {
            let capacity = LearningCampaignMachineCapacity.current()
            effectivePopulation = capacity.recommendedPopulation(current: population)
            effectiveEliteCount = min(eliteCount, effectivePopulation)
            let recommendation = capacity.recommendation(
                population: effectivePopulation,
                suiteCount: selectedSuites.count,
                episodes: episodes
            )
            effectiveWorkers = recommendation.workerCount
            effectiveCandidateEvaluationConcurrency = recommendation.candidateEvaluationConcurrency
            print("[evolve] auto-parallelism machine=\(capacity.summary) population=\(effectivePopulation) workers=\(effectiveWorkers) candidateConcurrency=\(effectiveCandidateEvaluationConcurrency) acceleratedSlots=\(recommendation.totalParallelSlots)/\(capacity.acceleratedParallelSlotBudget)")
        } else {
            effectivePopulation = population
            effectiveEliteCount = eliteCount
            effectiveWorkers = workers
            effectiveCandidateEvaluationConcurrency = candidateEvaluationConcurrency
        }
        let backend = ManasMLXEvolutionBackend(
            rootDirectory: artifactRoot.appendingPathComponent("candidates", isDirectory: true),
            variationProvider: makeVariationProvider()
        )
        let evaluator: any EvolutionCandidateEvaluating = ReferenceQuadrotorEvolutionRegressionEvaluator(
            task: learningCampaignRolloutTask(from: task),
            tier: learningCampaignTier(from: tier),
            cutPeriodSteps: cutPeriodSteps,
            suites: selectedSuites,
            episodes: episodes,
            workers: effectiveWorkers,
            robotManifestPath: model,
            artifactRoot: artifactRoot.appendingPathComponent("candidate-evaluations", isDirectory: true),
            minimumRewardAverage: effectiveMinimumRewardAverage,
            useQualityGating: !noQualityGate
        )
        let orchestrator = EvolutionRunOrchestrator(
            backend: backend,
            evaluator: evaluator
        )
        _ = await orchestrator.run(
            config: EvolutionRunConfig(
                taskID: task.rawValue,
                robotManifestID: model.isEmpty ? nil : model,
                robotManifestHash: model.isEmpty ? nil : model,
                configHash: "\(task.rawValue)-\(suites)-\(episodes)-\(effectiveWorkers)-\(effectiveCandidateEvaluationConcurrency)-\(searchStrategy.rawValue)",
                policyID: "manasMLX",
                populationSize: effectivePopulation,
                generationCount: generations,
                eliteCount: effectiveEliteCount,
                workerCount: effectiveWorkers,
                candidateEvaluationConcurrency: effectiveCandidateEvaluationConcurrency,
                searchStrategy: searchStrategy.trainingStrategy,
                bootstrapSource: bootstrapSource.trainingSource,
                worldModelUsage: worldModelUsage.trainingUsage,
                antitheticSampling: antitheticSampling,
                commonRandomSeed: commonRandomSeed,
                mutationRate: mutationRate,
                mutationNoiseScale: mutationNoiseScale,
                adaptiveMutation: EvolutionAdaptiveMutationConfig(enabled: adaptiveMutation),
                // attitude (and A1 swap/HF-stress suites) is not tensor-world
                // capable; allow isolated CPU-world fallback. Hover tasks keep the
                // strict accelerator contract.
                worldExecutionRequirement: task == .attitude
                    ? .preferAcceleratorSharedWorld
                    : .acceleratorSharedWorld,
                parentCheckpointID: snapshotURL.lastPathComponent,
                parentCheckpointURL: snapshotURL
            ),
            gatePolicy: EvolutionGatePolicy(
                eliteCount: effectiveEliteCount,
                minimumTaskPassRate: evolutionProfile.minimumTaskPassRate,
                maximumSafetyViolationRate: 0,
                minimumHoldTimeRatio: evolutionProfile.minimumHoldTimeRatio,
                maximumAltitudeErrorRatio: evolutionProfile.maximumAltitudeErrorRatio,
                minimumRewardAverage: effectiveMinimumRewardAverage,
                minimumImprovementOverIncumbent: minimumIncumbentImprovement,
                minimumNoveltyScore: minimumNoveltyScore
            ),
            artifactDirectory: artifactRoot
        )
        let artifacts = try GeneratedTrainingArtifactCompatibilityVerifier().loadEvolutionArtifacts(from: artifactRoot)
        let displayBestCandidateID = artifacts.eliteArchive.bestCandidateID
            ?? artifacts.generations.last?.bestCandidateID
            ?? "n/a"
        let displayBestFitness = artifacts.eliteArchive.bestFitness
            ?? artifacts.generations.last?.bestFitness
        print("[evolve] artifacts path=\(artifactRoot.path)")
        print("[evolve] terminal=\(artifacts.manifest.terminalState.rawValue) variation=\(variation.rawValue) evaluation=\(evaluation.rawValue) generations=\(artifacts.generations.count) candidates=\(artifacts.candidates.count) best=\(displayBestCandidateID) bestFitness=\(formatOptional(displayBestFitness)) elites=\(artifacts.eliteArchive.eliteCandidateIDs.joined(separator: ","))")
        print("[evolve] acceptedCheckpoint=\(artifacts.acceptedCheckpoint.checkpointURL?.path ?? "n/a") acceptedCandidate=\(artifacts.acceptedCheckpoint.candidateID ?? "n/a") bestCandidate=\(artifacts.acceptedCheckpoint.bestCandidateID ?? "n/a") bestCheckpoint=\(artifacts.acceptedCheckpoint.bestCheckpointURL?.path ?? "n/a") publishReasons=\(artifacts.acceptedCheckpoint.reasons.joined(separator: ",")) decision=\(artifacts.artifactDirectory.appendingPathComponent(EvolutionAcceptedCheckpointDecision.fileName).path)")
        printEvolutionSearchSummary(artifacts: artifacts, adaptiveMutation: adaptiveMutation)
        if !artifacts.acceptedCheckpoint.accepted {
            throw ExitCode.failure
        }
    }

    private func printEvolutionSearchSummary(
        artifacts: EvolutionRunArtifactBundle,
        adaptiveMutation: Bool
    ) {
        let manifest = artifacts.manifest
        let finalGeneration = artifacts.generations.last
        let incumbentCandidateID = artifacts.candidates.first { $0.isIncumbent == true }?.candidateID
        let incumbentFitness = incumbentCandidateID.flatMap { candidateID in
            artifacts.fitness.first { $0.candidateID == candidateID }?.scalarFitness
        }
        let bestQDCell = artifacts.qualityDiversityArchive.cells.max { lhs, rhs in
            if lhs.fitness == rhs.fitness {
                return lhs.candidateID > rhs.candidateID
            }
            return lhs.fitness < rhs.fitness
        }
        let bestFitness = artifacts.eliteArchive.bestFitness ?? finalGeneration?.bestFitness
        let bestVsIncumbentDelta = zipOptional(
            bestFitness,
            incumbentFitness
        ).map { best, incumbent in best - incumbent }
        print(
            "[evolve] strategy=\(manifest.searchStrategy.rawValue) bootstrap=\(manifest.bootstrapSource.rawValue) worldModel=\(manifest.worldModelUsage.rawValue) antithetic=\(manifest.antitheticSampling) commonSeed=\(manifest.commonRandomSeed) adaptiveMutation=\(adaptiveMutation)"
        )
        print(
            "[evolve] incumbent=\(incumbentCandidateID ?? "n/a") incumbentFitness=\(formatOptional(incumbentFitness)) bestVsIncumbentDelta=\(formatOptional(bestVsIncumbentDelta))"
        )
        print(
            "[evolve] qdCells=\(artifacts.qualityDiversityArchive.cells.count) qdBest=\(bestQDCell?.candidateID ?? "n/a") qdBestFitness=\(formatOptional(bestQDCell?.fitness)) qdArchive=\(artifacts.artifactDirectory.appendingPathComponent(EvolutionQualityDiversityArchive.fileName).path)"
        )
        print(
            "[evolve] finalMutationRate=\(formatOptional(finalGeneration?.mutationRate)) finalMutationNoiseScale=\(formatOptional(finalGeneration?.mutationNoiseScale)) finalQDCells=\(finalGeneration?.qualityDiversityCellCount ?? 0)"
        )
    }

    @MainActor
    private func makeVariationProvider() -> any ManasMLXGenomeVariationProviding {
        switch variation {
        case .copy:
            return ManasMLXFileBackedGenomeVariationProvider()
        case .gaussian:
            return ManasMLXGaussianMutationProvider(config: ManasMLXGaussianMutationConfig(
                noiseScale: 1,
                crossoverEnabled: !noCrossover
            ))
        }
    }

    @MainActor
    private func checkEvolutionInputs(snapshotURL: URL) throws {
        let preflight = try ManasMLXRuntimeReadinessService().report(
            for: ManasMLXRuntimeReadinessRequest(
                robotManifestPath: model,
                sourceCheckpointURL: snapshotURL,
                requireSourceCheckpoint: true
            )
        )
        print("[evolve] preflight mlx=\(preflight.mlxRuntimeReady) robotManifestLoaded=\(preflight.robotManifestLoaded) sourceCheckpointLoadable=\(preflight.sourceCheckpointLoadable)")
    }
}

struct RunLearningCampaign: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-learning-campaign",
        abstract: "Run a typed Swift learning campaign over one or more seeds."
    )

    @Option(help: "Task to optimize: lift or singleLift.")
    var task: LearningCampaignTask = .lift

    @Option(name: .customLong("source-checkpoint"), help: "Task-specific source checkpoint directory.")
    var sourceCheckpoint: String?

    @Option(name: .customLong("continue-from-artifact-root"), help: "Previous learning campaign artifact root to continue from.")
    var continueFromArtifactRoot: String?

    @Flag(name: .customLong("resume"), help: "Resume an interrupted campaign in place from each seed's last committed generation checkpoint.")
    var resume: Bool = false

    @Option(name: .customLong("resume-from-generation"), help: "When resuming, roll back to this generation index instead of the highest committed one.")
    var resumeFromGeneration: Int?

    @Option(name: .customLong("artifact-root"), help: "Directory where campaign artifacts are written.")
    var artifactRootPath: String

    @Option(help: "Comma-separated explicit campaign seed values.")
    var seeds: String?

    @Option(name: .customLong("seed-count"), help: "Generate sequential campaign seeds from 1 through this count.")
    var seedCount: Int = 1

    @Option(help: "Population size per seed.")
    var population: Int = 100

    @Option(help: "Maximum generation budget per seed. Normal completion is convergence or plateau early stopping.")
    var generations: Int = 1_000

    @Option(name: .customLong("elite-count"), help: "Number of candidates selected as parents.")
    var eliteCount: Int = 10

    @Option(help: "Worker count for rollout regression.")
    var workers: Int = 1

    @Option(name: .customLong("candidate-evaluation-concurrency"), help: "Maximum Manas candidate evaluations to run concurrently.")
    var candidateEvaluationConcurrency: Int = 100

    @Flag(name: .customLong("no-auto-parallelism"), help: "Disable machine-optimized population and evaluation concurrency.")
    var noAutoParallelism: Bool = false

    @Option(help: "Comma-separated M2 suite list: 6,7,8.")
    var suites: String = "6"

    @Option(help: "Episodes per candidate regression.")
    var episodes: Int = 1

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: LearningCampaignTier = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(name: .customLong("mutation-rate"), help: "Mutation rate passed to the ManasMLX variation provider.")
    var mutationRate: Double = 0.14

    @Option(name: .customLong("mutation-noise-scale"), help: "Gaussian mutation noise scale.")
    var mutationNoiseScale: Double = 0.025

    @Flag(name: .customLong("adaptive-mutation"), inversion: .prefixedNo, help: "Adapt mutation rate and noise scale after each generation gate result.")
    var adaptiveMutation: Bool = true

    @Option(name: .customLong("mutation-increase-factor"), help: "Adaptive mutation multiplier after a rejected generation.")
    var mutationIncreaseFactor: Double = 1.35

    @Option(name: .customLong("mutation-decay-factor"), help: "Adaptive mutation multiplier after an accepted generation.")
    var mutationDecayFactor: Double = 0.95

    @Option(name: .customLong("min-mutation-rate"), help: "Lower bound for adaptive mutation rate.")
    var minimumMutationRate: Double = 0

    @Option(name: .customLong("max-mutation-rate"), help: "Upper bound for adaptive mutation rate.")
    var maximumMutationRate: Double = 0.8

    @Option(name: .customLong("min-mutation-noise-scale"), help: "Lower bound for adaptive mutation noise scale.")
    var minimumMutationNoiseScale: Double = 0

    @Option(name: .customLong("max-mutation-noise-scale"), help: "Upper bound for adaptive mutation noise scale.")
    var maximumMutationNoiseScale: Double = 0.25

    @Option(name: .customLong("search-strategy"), help: "Evolution search strategy.")
    var searchStrategy: EvolutionSearchStrategy = .qualityDiversity

    @Option(help: "Candidate variation mode: gaussian or copy.")
    var variation: LearningCampaignVariation = .gaussian

    @Option(name: .customLong("min-reward-average"), help: "Override task default minimum reward average.")
    var minimumRewardAverage: Double?

    @Flag(name: .customLong("no-reinforcement-warmup"), help: "Disable the temporal CTBR PPO warmup before genetic evolution.")
    var noReinforcementWarmup: Bool = false

    @Option(name: .customLong("reinforcement-warmup-duration"), help: "Seconds of tensor-world rollout per candidate for PPO warmup.")
    var reinforcementWarmupDuration: Double = 2

    @Option(name: .customLong("reinforcement-warmup-iterations"), help: "PPO iterations for the temporal CTBR warmup.")
    var reinforcementWarmupIterations: Int = 1

    @Option(name: .customLong("reinforcement-warmup-learning-rate"), help: "Learning rate for temporal CTBR PPO warmup.")
    var reinforcementWarmupLearningRate: Double = 3e-4

    @Option(name: .customLong("reinforcement-warmup-max-batches"), help: "Optional maximum number of rollout batches used by PPO warmup.")
    var reinforcementWarmupMaxBatches: Int?

    @Option(name: .customLong("min-incumbent-improvement"), help: "Minimum strict scalar-fitness improvement over the incumbent checkpoint.")
    var minimumIncumbentImprovement: Double = 0

    @Option(name: .customLong("min-novelty-score"), help: "Minimum novelty score required for a candidate to enter the evolution archive.")
    var minimumNoveltyScore: Double?

    @Option(name: .customLong("resource-sample-seconds"), help: "Resource sample interval recorded in the campaign plan. Use 0 to disable resource samples.")
    var resourceSampleSeconds: Double = 30

    @Option(name: .customLong("artifact-retention"), help: "Artifact retention mode: full or compact.")
    var artifactRetention: LearningCampaignArtifactRetentionMode = .compact

    @Option(name: .customLong("autonomy-domain"), help: "Autonomy domain: automotive, groundRobot, aerialDrone, or manipulator.")
    var autonomyDomain: AutonomousOperationDomain = .aerialDrone

    @Option(name: .customLong("reinforcement-artifact"), help: "Optional accepted RL training-run artifact directory to attach as reinforcement stage evidence.")
    var reinforcementArtifactPath: String?

    @Flag(name: .customLong("skip-initial-parent-pass"), help: "Run starter evolution even when the source checkpoint does not yet pass the task gate.")
    var skipInitialParentPass: Bool = false

    @Option(name: .customLong("kp"), help: "IMU rate damping proportional gain.")
    var kp: Double = 0.35

    @Option(name: .customLong("kd"), help: "IMU rate damping derivative gain.")
    var kd: Double = 0.08

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain.")
    var yawDamping: Double = 0.04

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for ManasMLX rollout.")
    var noQualityGate: Bool = false

    @MainActor
    mutating func run() async throws {
        let trimmedSource = sourceCheckpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedContinuationRoot = continueFromArtifactRoot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !(trimmedSource.isEmpty == false && trimmedContinuationRoot.isEmpty == false) else {
            throw ValidationError("--source-checkpoint and --continue-from-artifact-root cannot both be set.")
        }
        // In-place resume (--resume) continues the SAME artifact root from durable
        // per-generation checkpoints; warm restart (--continue-from-artifact-root)
        // seeds a NEW root from a previous run's best checkpoint. They are distinct.
        guard !(resume && trimmedContinuationRoot.isEmpty == false) else {
            throw ValidationError("--resume and --continue-from-artifact-root cannot both be set.")
        }
        guard resumeFromGeneration == nil || resume else {
            throw ValidationError("--resume-from-generation requires --resume.")
        }
        if let resumeFromGeneration, resumeFromGeneration < 0 {
            throw ValidationError("--resume-from-generation must be >= 0.")
        }
        // The resume artifact root is non-empty by construction; the stop sentinel
        // lets an operator request a graceful, resumable stop by creating the file.
        let stopSentinelPath = artifactRootPath.isEmpty
            ? nil
            : URL(fileURLWithPath: artifactRootPath, isDirectory: true)
                .appendingPathComponent("RUN_CONTROL", isDirectory: true)
                .appendingPathComponent("STOP", isDirectory: false)
                .path
        let sourceCheckpointURL: URL
        if trimmedContinuationRoot.isEmpty == false {
            let previousArtifactRoot = URL(fileURLWithPath: trimmedContinuationRoot, isDirectory: true)
            sourceCheckpointURL = previousArtifactRoot
            print("[learning-campaign] continuation requested previousArtifactRoot=\(previousArtifactRoot.path)")
        } else {
            guard !trimmedSource.isEmpty else {
                throw ValidationError("--source-checkpoint or --continue-from-artifact-root is required.")
            }
            sourceCheckpointURL = URL(fileURLWithPath: trimmedSource, isDirectory: true)
        }
        let artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        let selectedSeeds = try seeds.map(parseCampaignSeeds)
        let selectedSuites = try parseRegressionSuites(suites)
        var resolvedPopulation = population
        var resolvedEliteCount = eliteCount
        var resolvedWorkers = workers
        var resolvedCandidateEvaluationConcurrency = candidateEvaluationConcurrency
        if !noAutoParallelism {
            let capacity = LearningCampaignMachineCapacity.current()
            resolvedPopulation = capacity.recommendedPopulation(current: resolvedPopulation)
            let recommendation = capacity.recommendation(
                population: resolvedPopulation,
                suiteCount: selectedSuites.count,
                episodes: episodes
            )
            resolvedEliteCount = min(max(1, resolvedEliteCount), resolvedPopulation)
            resolvedWorkers = recommendation.workerCount
            resolvedCandidateEvaluationConcurrency = recommendation.candidateEvaluationConcurrency
            print("[learning-campaign] auto-parallelism machine=\(capacity.summary) population=\(resolvedPopulation) workers=\(recommendation.workerCount) candidateConcurrency=\(recommendation.candidateEvaluationConcurrency) acceleratedSlots=\(recommendation.totalParallelSlots)/\(capacity.acceleratedParallelSlotBudget)")
        }
        let executor = ManasMLXTrainingRunExecutor()
        let configuration = TrainingRunConfiguration(
            trainingStageID: "evolution-search",
            trainingStageDisplayName: "Evolution Search",
            trainingStageKind: .evolution,
            scenarioSelection: TrainingScenarioSelection(
                suiteIDs: selectedSuites,
                episodesPerSuite: episodes,
                tier: TrainingDeterminismTier(cliTier: tier),
                cutPeriodSteps: cutPeriodSteps,
                explicitSeeds: selectedSeeds
            ),
            resources: TrainingResourcePlan(
                workerCount: resolvedWorkers,
                candidateEvaluationConcurrency: resolvedCandidateEvaluationConcurrency,
                resourceSampleSeconds: resourceSampleSeconds,
                // attitude scenarios (and the A1 swap/HF-stress suites) are not
                // tensor-world capable, so they must be allowed to fall back to
                // isolated CPU worlds. lift/singleLift hover stays on the strict
                // accelerator contract to keep GPU-batched evaluation fast.
                worldExecutionRequirement: task == .attitude
                    ? .preferAcceleratorSharedWorld
                    : .acceleratorSharedWorld
            ),
            evolution: TrainingEvolutionSettings(
                eliteCount: resolvedEliteCount,
                searchStrategy: searchStrategy,
                variation: TrainingVariationKind(cliVariation: variation),
                mutation: TrainingMutationSchedule(
                    rate: mutationRate,
                    noiseScale: mutationNoiseScale,
                    adaptiveEnabled: adaptiveMutation,
                    increaseFactor: mutationIncreaseFactor,
                    decayFactor: mutationDecayFactor,
                    minimumRate: minimumMutationRate,
                    maximumRate: maximumMutationRate,
                    minimumNoiseScale: minimumMutationNoiseScale,
                    maximumNoiseScale: maximumMutationNoiseScale
                ),
                minimumIncumbentImprovement: minimumIncumbentImprovement,
                minimumNoveltyScore: minimumNoveltyScore
            ),
            qualityGate: TrainingQualityGateSettings(
                enabled: !noQualityGate,
                minimumRewardAverage: minimumRewardAverage
            ),
            reinforcement: TrainingReinforcementSettings(
                warmupEnabled: !noReinforcementWarmup,
                requiresTemporalActorCritic: true,
                rolloutDuration: reinforcementWarmupDuration,
                iterations: reinforcementWarmupIterations,
                learningRate: reinforcementWarmupLearningRate,
                maxBatches: reinforcementWarmupMaxBatches
            ),
            control: TrainingControlSettings(
                robotManifestPath: model,
                kp: kp,
                kd: kd,
                yawDamping: yawDamping,
                hoverScale: hoverScale
            ),
            artifacts: TrainingArtifactPolicy(
                retention: TrainingArtifactRetentionKind(cliRetention: artifactRetention),
                allowsNonEmptyArtifactRoot: resume,
                requiresInitialParentPass: !skipInitialParentPass,
                reinforcementTrainingArtifactDirectory: reinforcementArtifactPath.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                },
                resumeInPlace: resume,
                resumeFromGeneration: resumeFromGeneration,
                stopSentinelPath: stopSentinelPath
            ),
            autonomyDomain: autonomyDomain
        )
        let trainingRequest = TrainingRunRequest(
            runID: TrainingRunID(artifactRoot.lastPathComponent),
            artifactRoot: artifactRoot,
            taskProfileID: task.profileID,
            policyContract: task.policyContract,
            actionContract: task.actionContract,
            sourceBundle: ModelBundleReference(
                bundleID: sourceCheckpointURL.lastPathComponent,
                kind: .source,
                url: sourceCheckpointURL
            ),
            seedCount: seedCount,
            populationSize: resolvedPopulation,
            generationLimit: generations,
            configuration: configuration
        )
        // A leftover sentinel from a prior run would stop this one immediately.
        if let stopSentinelPath {
            Self.removeStopSentinel(at: stopSentinelPath)
        }
        // Ctrl-C / SIGTERM request a graceful, resumable stop at the next generation
        // boundary by creating the stop sentinel the campaign polls. Per-generation
        // checkpoints already make a hard kill resumable; this makes an intentional
        // stop clean (terminal state .paused rather than a crash).
        let stopSignalSources = Self.installStopSignalHandlers(stopSentinelPath: stopSentinelPath)
        defer { stopSignalSources.forEach { $0.cancel() } }
        let handle: any TrainingRunHandle
        if trimmedContinuationRoot.isEmpty == false {
            handle = try await executor.resume(TrainingResumeRequest(
                runID: trainingRequest.runID,
                source: .artifactRoot(URL(fileURLWithPath: trimmedContinuationRoot, isDirectory: true)),
                destinationArtifactRoot: artifactRoot,
                taskProfileID: trainingRequest.taskProfileID,
                policyContract: trainingRequest.policyContract,
                actionContract: trainingRequest.actionContract,
                seedCount: trainingRequest.seedCount,
                populationSize: trainingRequest.populationSize,
                generationLimit: trainingRequest.generationLimit,
                configuration: configuration
            ))
        } else {
            handle = try await executor.start(trainingRequest)
        }
        var didComplete = false
        var didAcceptCheckpoint = false
        var terminalReason: String?
        for await event in handle.events {
            if let terminal = printTrainingRunEvent(event) {
                didComplete = true
                didAcceptCheckpoint = terminal.accepted
                terminalReason = terminal.reason
            }
        }
        print("[learning-campaign] artifacts path=\(artifactRoot.path)")
        // A graceful stop was requested (sentinel present): the run paused at a
        // generation boundary with durable checkpoints. Report cleanly and exit 0.
        if let stopSentinelPath, FileManager.default.fileExists(atPath: stopSentinelPath) {
            Self.removeStopSentinel(at: stopSentinelPath)
            print("[learning-campaign] paused — durable per-generation checkpoints written. Resume with: --resume --artifact-root \(artifactRoot.path)")
            return
        }
        guard didComplete else {
            throw ValidationError("learning campaign ended before publishing a terminal TrainingRunEvent.")
        }
        guard didAcceptCheckpoint else {
            throw ValidationError("learning campaign rejected: \(terminalReason ?? "checkpoint-not-accepted")")
        }
    }

    /// Removes the stop sentinel file if present (best effort: a leftover sentinel
    /// only affects graceful-stop detection, not checkpoint durability).
    static func removeStopSentinel(at path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("[learning-campaign] warning: could not clear stop sentinel \(path): \(error)")
        }
    }

    /// Creates the stop sentinel (and its RUN_CONTROL directory) to request a
    /// cooperative graceful stop at the next generation boundary.
    static func createStopSentinel(at path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: url)
        } catch {
            print("[learning-campaign] warning: could not create stop sentinel \(path): \(error)")
        }
    }

    /// Installs SIGINT/SIGTERM handlers that create the stop sentinel on a
    /// background queue (outside signal context, so file I/O is safe). Returns the
    /// sources to keep alive for the run's duration.
    static func installStopSignalHandlers(stopSentinelPath: String?) -> [any DispatchSourceSignal] {
        guard let stopSentinelPath else { return [] }
        let queue = DispatchQueue(label: "team.stamp.kuyu.stop-signal")
        return [SIGINT, SIGTERM].map { sig -> any DispatchSourceSignal in
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            source.setEventHandler {
                createStopSentinel(at: stopSentinelPath)
                print("\n[learning-campaign] stop requested — finishing the current generation, then pausing (resume with --resume).")
            }
            source.resume()
            return source
        }
    }

    private func parseCampaignSeeds(_ raw: String) throws -> [String] {
        let values = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else {
            throw ValidationError("--seeds must include at least one seed.")
        }
        var seenSeeds = Set<String>()
        var parsedSeeds: [String] = []
        for value in values {
            guard let seed = UInt64(value) else {
                throw ValidationError("--seeds contains an invalid unsigned integer seed: \(value)")
            }
            let canonicalValue = String(seed)
            guard seenSeeds.insert(canonicalValue).inserted else {
                throw ValidationError("--seeds contains a duplicate seed: \(canonicalValue)")
            }
            parsedSeeds.append(canonicalValue)
        }
        return parsedSeeds
    }

    private func printTrainingRunEvent(_ event: TrainingRunEvent) -> TrainingRunResultTerminalClassifier.Classification? {
        switch event {
        case .progress:
            return nil
        case .log(let log):
            let seed = log.seed.map { " seed=\($0)" } ?? ""
            let generation = log.generationIndex.map { " generation=\($0)" } ?? ""
            let candidate = log.candidateID.map { " candidate=\($0)" } ?? ""
            let progress = log.progressFraction.map { String(format: " progress=%.1f%%", $0 * 100) } ?? ""
            let metadata = log.metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            let suffix = metadata.isEmpty ? "" : " \(metadata)"
            print("[learning-campaign] \(log.level.rawValue) phase=\(log.phase)\(seed)\(generation)\(candidate)\(progress) message=\"\(log.message)\"\(suffix)")
            return nil
        case .started(let manifest):
            print("[learning-campaign] started runID=\(manifest.runID)")
            return nil
        case .iterationStarted(let iteration):
            print("[learning-campaign] iteration started iteration=\(iteration)")
            return nil
        case .suiteCompleted(let iteration, _, let score):
            print("[learning-campaign] suite completed iteration=\(iteration) score=\(score)")
            return nil
        case .datasetExported(let iteration, let directory, let count):
            print("[learning-campaign] dataset exported iteration=\(iteration) count=\(count) directory=\(directory)")
            return nil
        case .trainingCompleted(let iteration, let result):
            print("[learning-campaign] training completed iteration=\(iteration) loss=\(result.finalLoss)")
            return nil
        case .reinforcementTrainingCompleted(let iteration, let result):
            print("[learning-campaign] reinforcement completed iteration=\(iteration) reward=\(result.rewardAverage)")
            return nil
        case .convergenceUpdated(let summary):
            print("[learning-campaign] convergence accepted=\(summary.accepted) reason=\(summary.reason)")
            return nil
        case .completed(let result):
            let classification = TrainingRunResultTerminalClassifier().classify(result: result)
            print("[learning-campaign] completed terminalState=\(result.manifest.terminalState.rawValue) checkpointDecision=\(result.checkpointDecision.state.rawValue) terminalAcceptance=\(classification.status.rawValue) reason=\(classification.reason)")
            return classification
        }
    }
}

private extension LearningCampaignTask {
    var profileID: String {
        switch self {
        case .attitude:
            return "attitude-v1"
        case .lift:
            return "lift-v1"
        case .singleLift:
            return "singleLift-v1"
        }
    }

    var policyContract: LearningProjectPolicyContract {
        switch self {
        case .attitude:
            return ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract()
        case .lift:
            return ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract()
        case .singleLift:
            return .simpleFeedForward(
                observationDimension: 8,
                actionDimension: 1,
                actionEncoding: .directMotor
            )
        }
    }

    var actionContract: LearningProjectActionContract {
        switch self {
        case .attitude, .lift:
            return ReferenceQuadrotorLearningContracts.bodyRateActionContract()
        case .singleLift:
            return LearningProjectActionContract(
                schemaID: "single-prop-drive-v1",
                kind: .continuous,
                driveCount: 1,
                actuatorCount: 1,
                isBounded: true,
                channels: [
                    LearningProjectActionChannel(
                        index: 0,
                        name: "propellerThrust",
                        unit: "normalized",
                        normalizedLowerBound: 0,
                        normalizedUpperBound: 1,
                        outputTransform: .sigmoid
                    )
                ]
            )
        }
    }
}

private extension TrainingDeterminismTier {
    init(cliTier: LearningCampaignTier) {
        switch cliTier {
        case .tier0:
            self = .tier0
        case .tier1:
            self = .tier1
        case .tier2:
            self = .tier2
        }
    }
}

private extension TrainingVariationKind {
    init(cliVariation: LearningCampaignVariation) {
        switch cliVariation {
        case .copy:
            self = .copy
        case .gaussian:
            self = .gaussian
        }
    }
}

private extension TrainingArtifactRetentionKind {
    init(cliRetention: LearningCampaignArtifactRetentionMode) {
        switch cliRetention {
        case .compact:
            self = .compact
        case .full:
            self = .full
        }
    }
}

private func zipOptional<A, B>(_ lhs: A?, _ rhs: B?) -> (A, B)? {
    guard let lhs, let rhs else { return nil }
    return (lhs, rhs)
}

struct TrainWorldModel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "train-world-model",
        abstract: "Train a Manas world model from a Kuyu rollout dataset."
    )

    @Option(help: "Dataset directory containing meta.json and records.jsonl.")
    var dataset: String

    @Option(name: .customLong("save-model"), help: "Directory to save the world-model checkpoint and manifest.")
    var saveModelPath: String

    @Option(name: .customLong("sequence"), help: "Sequence length for world-model training.")
    var sequenceLength: Int = 8

    @Option(name: .customLong("epochs"), help: "Training epochs.")
    var epochs: Int = 1

    @Option(name: .customLong("lr"), help: "Learning rate.")
    var learningRate: Double = 0.001

    @Option(name: .customLong("max-batches"), help: "Maximum batches for smoke training.")
    var maxBatches: Int?

    mutating func run() async throws {
        try MLXRuntimeReadinessService().check()
        guard sequenceLength > 0 else {
            throw ValidationError("--sequence must be greater than 0.")
        }
        guard epochs > 0 else {
            throw ValidationError("--epochs must be greater than 0.")
        }
        guard learningRate.isFinite && learningRate > 0 else {
            throw ValidationError("--lr must be finite and greater than 0.")
        }
        let manifest = try M2TrainingService().trainWorldModel(
            datasetDirectory: URL(fileURLWithPath: dataset, isDirectory: true),
            saveDirectory: URL(fileURLWithPath: saveModelPath, isDirectory: true),
            sequenceLength: sequenceLength,
            epochs: epochs,
            learningRate: Float(learningRate),
            maxBatches: maxBatches
        )
        print("[world-model] saved checkpoint=\(manifest.checkpointPath) losses=\(manifest.losses)")
        if let stateCheckpoint = manifest.stateWorldModelCheckpointPath {
            print("[world-model] saved stateCheckpoint=\(stateCheckpoint) stateLosses=\(manifest.stateWorldModelLosses ?? [])")
        } else {
            print("[world-model] stateCheckpoint=none reason=dataset-missing-m2-state-fields")
        }
    }
}

struct ImagineTrain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "imagine-train",
        abstract: "Run a smoke imagination-training pass from a world-model manifest."
    )

    @Option(name: .customLong("world-model"), help: "World-model directory containing world-model-manifest.json.")
    var worldModelPath: String

    @Option(name: .customLong("save-model"), help: "Directory to save imagination-training checkpoint and manifest.")
    var saveModelPath: String

    @Option(help: "Imagination horizon.")
    var horizon: Int = 4

    @Option(help: "Training epochs.")
    var epochs: Int = 1

    mutating func run() async throws {
        try MLXRuntimeReadinessService().check()
        guard horizon > 0 else {
            throw ValidationError("--horizon must be greater than 0.")
        }
        guard epochs > 0 else {
            throw ValidationError("--epochs must be greater than 0.")
        }
        let manifest = try M2TrainingService().imagineTrain(
            worldModelDirectory: URL(fileURLWithPath: worldModelPath, isDirectory: true),
            saveDirectory: URL(fileURLWithPath: saveModelPath, isDirectory: true),
            horizon: horizon,
            epochs: epochs
        )
        print("[imagination] saved rollback=\(manifest.rollbackCheckpointPath) accepted=\(manifest.validationAccepted)")
        if let stateCheckpoint = manifest.stateWorldModelCheckpointPath {
            print("[imagination] validated stateCheckpoint=\(stateCheckpoint) reason=\(manifest.validationReason ?? "accepted")")
        }
    }
}

/// Staged self-verification harness. Runs a sequence of checks with per-stage CLI
/// output so the system can be validated incrementally without the GUI or a trained
/// checkpoint. Exits non-zero if any check fails.
struct Verify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Staged self-verification: MLX preflight, environment readiness, Tier-0 determinism, and A1 conformance suites (0–5), each reported as it runs."
    )

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier0

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path (optional; empty uses the reference baseline).")
    var model: String = ""

    @Option(help: "Scenarios per A1 suite stage.")
    var episodes: Int = 1

    @Option(name: .customLong("max-steps"), help: "Maximum steps per rollout episode. Omit for the full scenario duration (needed to reach mid-run swaps).")
    var maxSteps: Int?

    @Option(name: .customLong("artifact-root"), help: "Directory for verification artifacts.")
    var artifactRootPath: String = "/tmp/kuyu-verify"

    @Flag(name: .customLong("skip-mlx"), help: "Skip the MLX runtime preflight stage (pure-physics verification only).")
    var skipMLX: Bool = false

    @Option(help: "kp gain for the baseline controller.")
    var kp: Double = 2.0
    @Option(help: "kd gain for the baseline controller.")
    var kd: Double = 0.25
    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for the baseline controller.")
    var yawDamping: Double = 0.2
    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    mutating func run() async throws {
        let artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)

        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let gains = try ImuRateDampingCutGains(kp: kp, kd: kd, yawDamping: yawDamping, hoverThrustScale: hoverScale)
        let loadedRobot = try loadLoadedRobot(modelPath: model)
        let parameters = try makeRolloutParameters(task: .attitude, loadedRobot: loadedRobot, hoverThrustScale: hoverScale)
        let limits = try RolloutRunner.Limits.validated(maxStepsPerEpisode: maxSteps, maxWallTimeSeconds: nil)

        func baselineRollout(_ definitions: [ReferenceQuadrotorScenarioDefinition]) async throws -> RolloutSummary {
            let runner = RolloutRunner(
                parameters: parameters,
                schedule: schedule,
                determinism: determinism,
                hoverThrustScale: hoverScale,
                loadedRobot: loadedRobot,
                motorNerveRateLimitPerSecond: 100.0,
                motorNerveSmoothingTimeConstant: nil,
                limits: limits
            )
            let policy = KuyAtt1BaselinePolicyFactory(parameters: parameters, gains: gains, mode: .teacher)
            let episodeResults = try await runner.run(definitions: definitions, policyFactory: policy)
            return RolloutSummary(episodes: episodeResults)
        }

        var failures = 0
        let stageCount = skipMLX ? 3 : 4
        var stageIndex = 0
        func stage(_ name: String) { stageIndex += 1; print("[verify \(stageIndex)/\(stageCount)] \(name)") }
        func pass(_ detail: String) { print("[verify]   PASS — \(detail)") }
        func fail(_ detail: String) { failures += 1; print("[verify]   FAIL — \(detail)") }

        // Stage 1: MLX runtime preflight.
        if !skipMLX {
            stage("MLX runtime preflight")
            do {
                let report = try ManasMLXRuntimeReadinessService().report(
                    for: ManasMLXRuntimeReadinessRequest(robotManifestPath: model)
                )
                if report.mlxRuntimeReady {
                    pass("MLX/Metal runtime ready (robotManifestLoaded=\(report.robotManifestLoaded))")
                } else {
                    fail("MLX runtime not ready")
                }
            } catch {
                fail("MLX preflight threw: \(error)")
            }
        }

        // Stage 2: environment readiness for the attitude task (teacher baseline).
        stage("Environment readiness (attitude)")
        do {
            let report = try await ReferenceQuadrotorEnvironmentReadinessChecker().check(
                tasks: [.attitude],
                controller: .teacherActiveAltitudeHold,
                parameters: parameters,
                schedule: schedule,
                determinism: determinism,
                gains: gains,
                robotManifestPath: model,
                embodiment: loadedRobot?.embodiment,
                artifactRoot: artifactRoot.appendingPathComponent("environment-readiness", isDirectory: true)
            )
            for task in report.tasks {
                print("[verify]   env task=\(task.task) ready=\(task.ready) score=\(String(format: "%.3f", task.score))")
            }
            if report.allReady {
                pass("all attitude environments ready")
            } else {
                fail("environment not ready")
            }
        } catch {
            fail("readiness threw: \(error)")
        }

        // Stage 3: Tier-0 determinism — A1 Suite-1 run twice must be bit-exact.
        stage("Tier-0 determinism (A1 Suite-1, bit-exact replay)")
        do {
            let definitions = try makeRolloutDefinitions(task: .attitude, suite: 1, episodes: episodes)
            let first = try await baselineRollout(definitions)
            let second = try await baselineRollout(definitions)
            if first.rewardSum == second.rewardSum {
                pass("identical rewardSum across two runs (\(String(format: "%.6f", first.rewardSum)))")
            } else {
                fail("rewardSum differs: \(first.rewardSum) vs \(second.rewardSum)")
            }
        } catch {
            fail("determinism stage threw: \(error)")
        }

        // Stage 4: A1 conformance suites 0…5 — verify stressor injection and that each runs.
        stage("A1 conformance suites (Suite-0 … Suite-5)")
        for level in A1ConformanceSuite.Level.allCases {
            do {
                let definitions = try makeRolloutDefinitions(task: .attitude, suite: level.rawValue, episodes: episodes)
                let swapCount = definitions.reduce(0) { $0 + $1.swapEvents.count }
                let hfCount = definitions.reduce(0) { $0 + $1.hfEvents.count }
                // Warmup must inject no stress; every other suite must inject at least one event.
                let injectionOK = level == .warmup
                    ? (swapCount + hfCount == 0)
                    : (swapCount + hfCount > 0)
                let summary = try await baselineRollout(definitions)
                if !definitions.isEmpty && injectionOK {
                    pass("\(level.suiteID) scenarios=\(definitions.count) swaps=\(swapCount) hf=\(hfCount) ran=\(summary.episodeCount) failures=\(summary.failureCount)")
                } else {
                    fail("\(level.suiteID) scenarios=\(definitions.count) swaps=\(swapCount) hf=\(hfCount) (injection mismatch)")
                }
            } catch {
                fail("\(level.suiteID) threw: \(error)")
            }
        }

        print("")
        if failures == 0 {
            print("[verify] ALL CHECKS PASSED")
        } else {
            print("[verify] \(failures) CHECK(S) FAILED")
            throw ExitCode.failure
        }
    }
}

func makeDeterminism(tier: TierChoice) throws -> DeterminismConfig {
    switch tier {
    case .tier0:
        return try DeterminismConfig(tier: .tier0)
    case .tier1:
        return try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
    case .tier2:
        return try DeterminismConfig(tier: .tier2)
    }
}

private func learningCampaignTier(from tier: TierChoice) -> LearningCampaignTier {
    switch tier {
    case .tier0:
        return .tier0
    case .tier1:
        return .tier1
    case .tier2:
        return .tier2
    }
}

private func learningCampaignRolloutTask(from task: RolloutTaskChoice) -> LearningCampaignRolloutTask {
    switch task {
    case .attitude:
        return .attitude
    case .lift:
        return .lift
    case .singleLift:
        return .singleLift
    }
}

func loadParameters(modelPath: String) throws -> ReferenceQuadrotorParameters {
    let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .baseline }

    let loader = KuyuModelLoader()
    let embodiment = try loader.loadRobot(path: trimmed)
    let inertial = try loader.loadPlantInertialProperties(robot: embodiment)
    return try ReferenceQuadrotorParameters.reference(
        from: inertial,
        robotID: embodiment.manifest.robotID
    )
}

func loadEmbodiment(modelPath: String) throws -> EmbodimentContract? {
    let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let loader = KuyuModelLoader()
    let embodiment = try loader.loadRobot(path: trimmed)
    return embodiment.embodiment
}

private func loadLoadedRobot(modelPath: String) throws -> LoadedKuyuRobot? {
    let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let loader = KuyuModelLoader()
    return try loader.loadRobot(path: trimmed)
}

private func score(from summary: ValidationSummary) -> Double {
    var score = summary.suitePassed ? 1.0 : 0.0
    if let worstOvershoot = summary.aggregate.worstOvershootDegrees {
        score -= min(1.0, worstOvershoot / 90.0) * 0.4
    }
    if let recovery = summary.aggregate.averageRecoveryTime {
        score -= min(1.0, recovery / 5.0) * 0.3
    }
    if let hf = summary.aggregate.averageHfStabilityScore {
        score += max(0.0, min(hf, 1.0)) * 0.2
    }
    return score
}

private func printSummary(output: KuyAtt1RunOutput) {
    let summary = output.summary
    let aggregate = summary.aggregate
    let overshoot = aggregate.worstOvershootDegrees.map { String(format: "%.2f", $0) } ?? "n/a"
    let recovery = aggregate.averageRecoveryTime.map { String(format: "%.2f", $0) } ?? "n/a"
    let hf = aggregate.averageHfStabilityScore.map { String(format: "%.2f", $0) } ?? "n/a"
    print("passed=\(summary.suitePassed) scenarios=\(summary.evaluations.count) overshoot=\(overshoot) recovery=\(recovery) hf=\(hf)")
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

private func makeRolloutDefinitions(
    task: RolloutTaskChoice,
    suite: Int?,
    episodes: Int,
    useTrainingSuite: Bool = false
) throws -> [ReferenceQuadrotorScenarioDefinition] {
    if useTrainingSuite {
        return try makeTrainingSuiteDefinitions(task: task, suite: suite, episodes: episodes)
    }
    if let suite {
        return try RegressionScenarioCatalog.scenarios(
            for: learningCampaignRolloutTask(from: task),
            suite: suite,
            episodeCount: episodes
        )
    }

    switch task {
    case .attitude:
        return try KuyAtt1Suite().scenarios()
    case .lift:
        return try KuyLiftSuite().scenarios()
    case .singleLift:
        return try KuySingleLiftSuite().scenarios()
    }
}

private func makeTrainingSuiteDefinitions(
    task: RolloutTaskChoice,
    suite: Int?,
    episodes: Int
) throws -> [ReferenceQuadrotorScenarioDefinition] {
    switch task {
    case .singleLift:
        let definitions = try KuyuSingleLiftTrainingSuite().scenarios()
        guard !definitions.isEmpty else {
            throw ValidationError("No singleLift training definitions are available.")
        }
        return try (0..<max(episodes, definitions.count)).map { index in
            try singleLiftTrainingDefinition(
                task: task,
                suite: suite ?? 6,
                index: index,
                definition: definitions[index % definitions.count]
            )
        }
    case .lift:
        return try RegressionScenarioCatalog.scenarios(
            for: learningCampaignRolloutTask(from: task),
            suite: suite ?? 6,
            episodeCount: episodes
        )
    case .attitude:
        return try makeRolloutDefinitions(task: task, suite: suite, episodes: episodes)
    }
}

private func singleLiftTrainingDefinition(
    task: RolloutTaskChoice,
    suite: Int,
    index: Int,
    definition: ReferenceQuadrotorScenarioDefinition
) throws -> ReferenceQuadrotorScenarioDefinition {
    guard task == .singleLift else { return definition }
    let scenarioIndex = index + 1
    return ReferenceQuadrotorScenarioDefinition(
        config: try ScenarioConfig(
            id: try ScenarioID("KUY-SLIFT-TRAIN-M2-S\(suite)/SCN-\(scenarioIndex)"),
            seed: ScenarioSeed(definition.config.seed.rawValue &+ UInt64(suite * 10_000 + index)),
            duration: definition.config.duration,
            timeStep: definition.config.timeStep
        ),
        kind: definition.kind,
        initialPosition: definition.initialPosition,
        initialAttitude: definition.initialAttitude,
        initialAngularVelocity: definition.initialAngularVelocity,
        safetyEnvelope: definition.safetyEnvelope,
        liftEnvelope: definition.liftEnvelope,
        torqueEvents: definition.torqueEvents,
        actuatorDegradation: definition.actuatorDegradation,
        gyroDriftScale: definition.gyroDriftScale,
        swapEvents: definition.swapEvents,
        hfEvents: definition.hfEvents
    )
}

private func simulationTaskMode(from task: RolloutTaskChoice) -> SimulationTaskMode {
    switch task {
    case .attitude:
        return .attitude
    case .lift:
        return .lift
    case .singleLift:
        return .singleLift
    }
}

private func controllerSelection(from controller: ControllerChoice) -> ControllerSelection {
    switch controller {
    case .activeAltitudeHold:
        return .teacherActiveAltitudeHold
    case .sensorBaseline:
        return .sensorBaseline
    case .manasMLX:
        return .manasMLX
    }
}

private func parseRegressionControllers(_ raw: String) throws -> [ControllerChoice] {
    let values = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !values.isEmpty else {
        throw ValidationError("--controllers must include at least one controller.")
    }
    return try values.map { value in
        guard let controller = ControllerChoice(rawValue: value) else {
            throw ValidationError("--controllers contains unsupported controller: \(value)")
        }
        return controller
    }
}

private func makeRolloutParameters(
    task: RolloutTaskChoice,
    loadedRobot: LoadedKuyuRobot? = nil,
    hoverThrustScale: Double = 1.0
) throws -> ReferenceQuadrotorParameters {
    guard hoverThrustScale.isFinite, hoverThrustScale > 0 else {
        throw ValidationError("--hover-scale must be finite and greater than 0.")
    }

    if let loadedRobot {
        let loader = KuyuModelLoader()
        let inertial = try loader.loadPlantInertialProperties(robot: loadedRobot)
        let parameters = try ReferenceQuadrotorParameters.reference(
            from: inertial,
            robotID: loadedRobot.manifest.robotID
        )
        guard task == .singleLift else { return parameters }
        return try KuyuSingleLiftParameterTuning.tuned(
            parameters: parameters,
            hoverThrustScale: hoverThrustScale
        )
    }

    guard task == .singleLift else { return .baseline }
    return try KuyuSingleLiftParameterTuning.tuned(
        parameters: .baseline,
        hoverThrustScale: hoverThrustScale
    )
}

private func rolloutDefinitionKey(scenarioId: String, seed: UInt64) -> String {
    "\(scenarioId)#\(seed)"
}

private func safePathComponent(_ raw: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.="))
    let scalars = raw.unicodeScalars.map { scalar in
        allowed.contains(scalar) ? Character(scalar) : "_"
    }
    return String(scalars)
}

func parseDescendingVector(_ raw: String, optionName: String = "--descending") throws -> [Double]? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard !parts.isEmpty else {
        return nil
    }

    var vector: [Double] = []
    vector.reserveCapacity(parts.count)
    for part in parts {
        guard !part.isEmpty else {
            throw ValidationError("Invalid \(optionName) value ''. Use comma-separated finite numbers.")
        }
        guard let value = Double(part), value.isFinite else {
            throw ValidationError("Invalid \(optionName) value '\(part)'. Use comma-separated finite numbers.")
        }
        vector.append(value)
    }
    return vector
}

func parseDescendingProgram(_ raw: String) throws -> DescendingIntentProgram? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let frameSpecs = trimmed.split(separator: ";", omittingEmptySubsequences: false)
    var keyframes: [DescendingIntentProgram.Keyframe] = []
    keyframes.reserveCapacity(frameSpecs.count)

    for frameSpec in frameSpecs {
        let entry = frameSpec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else {
            throw ValidationError("Invalid --descending-program frame ''. Use 'time:values;time:values'.")
        }
        guard let separator = entry.firstIndex(of: ":") else {
            throw ValidationError("Invalid --descending-program frame '\(entry)'. Missing ':'.")
        }

        let timeToken = String(entry[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let valuesToken = String(entry[entry.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let time = Double(timeToken), time.isFinite else {
            throw ValidationError("Invalid --descending-program time '\(timeToken)'.")
        }
        guard let values = try parseDescendingVector(valuesToken, optionName: "--descending-program") else {
            throw ValidationError("Invalid --descending-program values '\(valuesToken)'.")
        }

        do {
            let frame = try DescendingIntentProgram.Keyframe(time: time, values: values)
            keyframes.append(frame)
        } catch {
            throw ValidationError("Invalid --descending-program frame '\(entry)': \(error)")
        }
    }

    do {
        return try DescendingIntentProgram(keyframes: keyframes)
    } catch {
        throw ValidationError("Invalid --descending-program: \(error)")
    }
}
