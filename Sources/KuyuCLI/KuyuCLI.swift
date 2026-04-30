import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLX
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

@main
struct KuyuCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kuyu",
        abstract: "Kuyu training world command-line interface.",
        subcommands: [Run.self, Rollout.self, Loop.self, ProbeManas.self, ProbeManasSuite.self, TrainManasCore.self, MixTrainingDatasets.self, EvaluateManasCheckpoint.self, CheckEnvironments.self, CheckTrainingHarness.self, CheckTrainingHarnessSweep.self, CheckKuyuRegression.self, CheckKuyuRegressionMatrix.self, EvolveManas.self, TrainWorldModel.self, ImagineTrain.self]
    )
}

enum TierChoice: String, CaseIterable, ExpressibleByArgument {
    case tier0
    case tier1
    case tier2
}

enum ControllerChoice: String, CaseIterable, ExpressibleByArgument {
    case baseline
    case teacherBaseline
    case sensorBaseline
    case manasMLX
}

enum RolloutTaskChoice: String, CaseIterable, ExpressibleByArgument {
    case attitude
    case lift
    case singleLift
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

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run a single KUY-ATT-1 suite.")

    @Option(help: "Controller to use: teacherBaseline, sensorBaseline, or manasMLX. The legacy baseline alias maps to teacherBaseline.")
    var controller: ControllerChoice = .teacherBaseline

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Model descriptor path (optional).")
    var model: String = ""

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
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let parameters = try loadParameters(modelPath: model)
        let descriptor = try loadDescriptor(modelPath: model)
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

        let output: KuyAtt1RunOutput
        switch controller {
        case .baseline, .teacherBaseline:
            let runner = KuyAtt1Runner(
                parameters: parameters,
                schedule: schedule,
                determinism: determinism,
                noise: .zero,
                gains: gains,
                baselineMode: .teacher
            )
            output = try await runner.runWithLogs()
        case .sensorBaseline:
            let runner = KuyAtt1Runner(
                parameters: parameters,
                schedule: schedule,
                determinism: determinism,
                noise: .zero,
                gains: gains,
                baselineMode: .sensor
            )
            output = try await runner.runWithLogs()
        case .manasMLX:
            try MLXRuntimePreflight().check()
            let request = SimulationRunRequest(
                controller: .manasMLX,
                gains: gains,
                cutPeriodSteps: cutPeriodSteps,
                noise: .zero,
                determinism: determinism,
                modelDescriptorPath: model,
                overrideParameters: model.isEmpty ? nil : parameters,
                useAux: !noAux,
                useQualityGating: !noQualityGate,
                descendingVector: descendingVector,
                descendingProgram: parsedDescendingProgram
            )
            let store = ManasMLXModelStore()
            output = try await store.runManasMLX(
                parameters: parameters,
                schedule: schedule,
                request: request,
                descriptor: descriptor,
                control: nil
            )
        }

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

    @Option(help: "Controller to use: teacherBaseline or sensorBaseline. The legacy baseline alias maps to teacherBaseline.")
    var controller: ControllerChoice = .teacherBaseline

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

    @Option(help: "Model descriptor path (optional).")
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

    @Option(name: .customLong("export-dataset"), help: "Directory to export rollout dataset.")
    var exportDatasetPath: String?

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
            case .baseline, .teacherBaseline:
                return .teacher
            case .sensorBaseline:
                return .sensor
            case .manasMLX:
                return .teacher
            }
        }()

        let suiteDefinitions = try makeRolloutDefinitions(task: task, suite: suite, episodes: episodes)
        let definitions = Array(suiteDefinitions.prefix(min(episodes, suiteDefinitions.count)))
        if definitions.count < episodes {
            print("[rollout] requested episodes=\(episodes) available=\(definitions.count); using available KUY-ATT-1 scenarios")
        }

        let loadedDescriptor = try loadLoadedDescriptor(modelPath: model)
        let rolloutParameters = try makeRolloutParameters(task: task, loadedDescriptor: loadedDescriptor)
        let limits = try RolloutRunner.Limits.validated(
            maxStepsPerEpisode: maxSteps,
            maxWallTimeSeconds: maxWallTime
        )
        let runner = RolloutRunner(
            parameters: rolloutParameters,
            schedule: schedule,
            determinism: determinism,
            hoverThrustScale: hoverScale,
            loadedDescriptor: loadedDescriptor,
            motorNerveRateLimitPerSecond: mode == .teacher ? 100.0 : 2.0,
            motorNerveSmoothingTimeConstant: mode == .teacher ? nil : 0.08,
            limits: limits
        )
        let policyFactory: any ReferenceQuadrotorPolicyFactory
        switch controller {
        case .manasMLX:
            let trimmed = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ValidationError("--snapshot is required for manasMLX rollout. Shared ManasMLXModelStore rollout is intentionally unsupported.")
            }
            policyFactory = ManasMLXRolloutPolicyFactory(
                snapshotDirectory: URL(fileURLWithPath: trimmed, isDirectory: true)
            )
        case .baseline, .teacherBaseline, .sensorBaseline:
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

    @Option(help: "Model descriptor path (optional).")
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
        let descriptor = try loadDescriptor(modelPath: model)
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
            modelDescriptorPath: model,
            overrideParameters: model.isEmpty ? nil : parameters,
            useAux: !noAux,
            useQualityGating: !noQualityGate,
            descendingVector: descendingVector,
            descendingProgram: parsedDescendingProgram
        )

        let scenarioStore = ManasMLXModelStore()
        let workerStore = ManasMLXModelStore()
        try MLXRuntimePreflight().check()

        let checkpointDirectory = saveModelPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let orchestrator = TrainingRunOrchestrator(
            scenarioExecutor: CLIScenarioExecutor(
                store: scenarioStore,
                parameters: parameters,
                schedule: schedule,
                descriptor: descriptor
            ),
            backend: ManasMLXTrainingBackend(
                runtime: ManasMLXTrainingRuntime(modelStore: workerStore),
                saveDirectory: checkpointDirectory
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
            artifactDirectory: datasetRoot
        ) { event in
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
        }
        print("[loop] artifacts path=\(datasetRoot.path)")
        print("[loop] terminal=\(result.manifest.terminalState.rawValue) accepted=\(result.convergence.accepted) reason=\(result.convergence.reason)")
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

    @Option(help: "Model descriptor path.")
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
        let preflight = try ManasMLXE2EPreflight().check(
            descriptorPath: model,
            sourceCheckpointURL: sourceCheckpointURL
        )
        print("[probe] preflight mlx=\(preflight.mlxRuntimeReady) descriptorLoaded=\(preflight.descriptorLoaded) sourceCheckpointLoadable=\(preflight.sourceCheckpointLoadable)")

        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let parameters = try loadParameters(modelPath: model)
        let descriptor = try loadDescriptor(modelPath: model)
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
            controller: .teacherBaseline,
            taskMode: taskMode,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            modelDescriptorPath: model,
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
            modelDescriptorPath: model,
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
                descriptorID: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : model,
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
                    descriptorID: sourceSnapshot?.descriptorID,
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
                .appendingPathComponent("candidate-checkpoints", isDirectory: true)
        )
        let probe = TrainingProbeOrchestrator(
            scenarioExecutor: CLITrainingProbeExecutor(
                teacherRequest: teacherRequest,
                initialStore: initialStore,
                trainedStore: trainedStore,
                parameters: parameters,
                schedule: schedule,
                descriptor: descriptor
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
        let validated = try TrainingProbeArtifactValidator().loadAndValidate(from: artifactRoot)
        print("[probe] artifactValid=true trainingRun=\(validated.training.manifest.runID) metrics=\(validated.training.metrics.count)")
        print("[probe] trainingCheckpoint=\(result.comparison.checkpointDecision.rawValue) probeCheckpoint=\(result.probeCheckpointDecision.state.rawValue) reload=\(result.comparison.reloadSucceeded)")
        print("[probe] selectedCheckpoint role=\(result.comparison.selectedCheckpointRole.rawValue) path=\(result.comparison.selectedCheckpointURL?.path ?? "n/a")")
        print("[probe] probeAccepted=\(result.comparison.probeAccepted) reasons=\(result.comparison.probeRejectionReasons.joined(separator: ","))")
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

    @Option(help: "Model descriptor path.")
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
            let artifacts = try TrainingProbeArtifactValidator().loadAndValidate(from: taskRoot)
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
    var epochs: Int = 1

    @Option(name: .customLong("lr"), help: "Learning rate.")
    var learningRate: Double = 0.001

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

        print("[train-manas-core] dataset=\(datasetURL.path)")
        print("[train-manas-core] checkpoint=\(outputURL.path)")
        print("[train-manas-core] model=\(manifest.name) finalLoss=\(String(format: "%.6f", result.finalLoss)) epochs=\(result.epochs)")
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

    @Option(help: "Model descriptor path.")
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

    @MainActor
    mutating func run() async throws {
        let checkpointURL = URL(fileURLWithPath: checkpointPath, isDirectory: true)
        let artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        _ = try ManasMLXE2EPreflight().check(
            descriptorPath: model,
            sourceCheckpointURL: checkpointURL
        )
        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let parameters = try loadParameters(modelPath: model)
        let descriptor = try loadDescriptor(modelPath: model)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )
        let taskMode = simulationTaskMode(from: task)
        let teacherRequest = SimulationRunRequest(
            controller: .teacherBaseline,
            taskMode: taskMode,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            modelDescriptorPath: model,
            overrideParameters: model.isEmpty ? nil : parameters,
            useAux: true,
            useQualityGating: !noQualityGate
        )
        let policyRequest = SimulationRunRequest(
            controller: .manasMLX,
            taskMode: taskMode,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            modelDescriptorPath: model,
            overrideParameters: model.isEmpty ? nil : parameters,
            useAux: true,
            useQualityGating: !noQualityGate
        )

        let store = ManasMLXModelStore()
        let runtime = KuyuScenarioRuntime(modelStore: store)
        let teacherOutput = try await runtime.run(
            request: teacherRequest,
            parameters: parameters,
            schedule: schedule,
            descriptor: descriptor,
            control: nil
        )
        _ = try store.loadModel(from: checkpointURL)
        let policyOutput = try await store.runManasMLX(
            parameters: parameters,
            schedule: schedule,
            request: policyRequest,
            descriptor: descriptor,
            control: nil
        )
        let teacher = TrainingProbeRunSummary(stage: .teacherBaseline, output: teacherOutput)
        let policy = TrainingProbeRunSummary(stage: .initialPolicy, output: policyOutput)
        let summary = ManasCheckpointEvaluationSummary(
            evaluationID: "checkpoint-eval-\(UUID().uuidString)",
            startedAt: Date(),
            task: task.rawValue,
            checkpointPath: checkpointURL.path,
            teacher: teacher,
            policy: policy
        )

        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(teacher).write(
            to: artifactRoot.appendingPathComponent("teacher-run.json"),
            options: [.atomic]
        )
        try encoder.encode(policy).write(
            to: artifactRoot.appendingPathComponent("policy-run.json"),
            options: [.atomic]
        )
        try encoder.encode(summary).write(
            to: artifactRoot.appendingPathComponent("checkpoint-evaluation.json"),
            options: [.atomic]
        )

        print("[evaluate-manas-checkpoint] task=\(task.rawValue) policyPassed=\(summary.policyPassed) score=\(String(format: "%.6f", summary.policyScore)) teacherScore=\(String(format: "%.6f", summary.teacherScore))")
        print("[evaluate-manas-checkpoint] motorMAE=\(formatOptional(summary.teacherMotorAverageMAE)) driveMAE=\(formatOptional(summary.teacherDriveAverageMAE)) finalAltitudeDelta=\(formatOptional(summary.teacherFinalAltitudeDelta)) failures=\(summary.policyFailureReasons.joined(separator: ","))")
        print("[evaluate-manas-checkpoint] artifacts path=\(artifactRoot.path)")
    }
}

private struct ManasCheckpointEvaluationSummary: Codable {
    let evaluationID: String
    let startedAt: Date
    let task: String
    let checkpointPath: String
    let teacherScore: Double
    let policyScore: Double
    let scoreDeltaFromTeacher: Double
    let teacherPassed: Bool
    let policyPassed: Bool
    let policyFailureReasons: [String]
    let teacherDriveAverageMAE: Double?
    let teacherMotorAverageMAE: Double?
    let teacherFinalAltitudeDelta: Double?
    let policyAverageMotorFinalOutputByIndex: [Double]?
    let teacherAverageMotorFinalOutputByIndex: [Double]?

    init(
        evaluationID: String,
        startedAt: Date,
        task: String,
        checkpointPath: String,
        teacher: TrainingProbeRunSummary,
        policy: TrainingProbeRunSummary
    ) {
        self.evaluationID = evaluationID
        self.startedAt = startedAt
        self.task = task
        self.checkpointPath = checkpointPath
        self.teacherScore = teacher.score
        self.policyScore = policy.score
        self.scoreDeltaFromTeacher = policy.score - teacher.score
        self.teacherPassed = teacher.suitePassed
        self.policyPassed = policy.suitePassed
        self.policyFailureReasons = policy.diagnostics.failureReasons
        self.teacherDriveAverageMAE = meanAbsoluteError(
            policy.diagnostics.averageDriveActivationByIndex,
            teacher.diagnostics.averageDriveActivationByIndex
        )
        self.teacherMotorAverageMAE = meanAbsoluteError(
            policy.diagnostics.averageMotorFinalOutputByIndex,
            teacher.diagnostics.averageMotorFinalOutputByIndex
        )
        self.teacherFinalAltitudeDelta = delta(
            policy.diagnostics.finalAltitudeZ,
            teacher.diagnostics.finalAltitudeZ
        )
        self.policyAverageMotorFinalOutputByIndex = policy.diagnostics.averageMotorFinalOutputByIndex
        self.teacherAverageMotorFinalOutputByIndex = teacher.diagnostics.averageMotorFinalOutputByIndex
    }
}

private func meanAbsoluteError(_ lhs: [Double]?, _ rhs: [Double]?) -> Double? {
    guard let lhs, let rhs, !lhs.isEmpty, lhs.count == rhs.count else {
        return nil
    }
    return zip(lhs, rhs).reduce(0.0) { partial, pair in
        partial + abs(pair.0 - pair.1)
    } / Double(lhs.count)
}

private func delta(_ lhs: Double?, _ rhs: Double?) -> Double? {
    guard let lhs, let rhs else {
        return nil
    }
    return lhs - rhs
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

    @Option(help: "Baseline controller to validate: teacherBaseline or sensorBaseline.")
    var controller: ControllerChoice = .teacherBaseline

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Model descriptor path.")
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
            throw ValidationError("check-environments validates baseline environments only. Use teacherBaseline or sensorBaseline.")
        }

        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let parameters = try loadParameters(modelPath: model)
        let descriptor = try loadDescriptor(modelPath: model)
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

        let report = try await KuyuEnvironmentReadinessChecker().check(
            tasks: selectedTasks,
            controller: selectedController,
            parameters: parameters,
            schedule: schedule,
            determinism: determinism,
            gains: gains,
            modelDescriptorPath: model,
            descriptor: descriptor,
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

    @Option(help: "Model descriptor path.")
    var model: String = ""

    @Option(name: .customLong("artifact-root"), help: "Directory where harness artifacts are written.")
    var artifactRootPath: String?

    @Option(name: .customLong("source-checkpoint"), help: "Optional source checkpoint directory to continue probe attempts from.")
    var sourceCheckpointPath: String?

    @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
    var sequenceLength: Int = 8

    @Option(name: .customLong("epochs"), help: "Epochs for the supervised ManasMLX probe.")
    var epochs: Int = 50

    @Option(name: .customLong("lr"), help: "Learning rate for the supervised ManasMLX probe.")
    var learningRate: Double = 0.0001

    @Option(name: .customLong("max-batches"), help: "Maximum training batches for the supervised ManasMLX probe.")
    var maxBatches: Int = 35

    @Option(help: "Maximum probe attempts per task. Each attempt writes separate artifacts.")
    var attempts: Int = 3

    @Option(name: .customLong("recovery-repeat"), help: "Repeat recovery relabel datasets this many times when mixing retry training data.")
    var recoveryRepeat: Int = 3

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
        let descriptor = try loadDescriptor(modelPath: model)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )

        let environmentRoot = artifactRoot.appendingPathComponent("environment-readiness", isDirectory: true)
        let environmentReport = try await KuyuEnvironmentReadinessChecker().check(
            tasks: [.lift, .singleLift],
            controller: .teacherBaseline,
            parameters: parameters,
            schedule: schedule,
            determinism: determinism,
            gains: gains,
            modelDescriptorPath: model,
            descriptor: descriptor,
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
                let repairSourceCheckpointURL = repairSourceCheckpointURL(from: result)
                currentSourceCheckpointURL = repairSourceCheckpointURL
                if let recoveryDatasetURL = acceptedRecoveryDatasetURL(from: result) {
                    recoveryDatasetURLs.append(recoveryDatasetURL)
                }
                let artifacts = try TrainingProbeArtifactValidator().loadAndValidate(from: taskRoot)
                let taskSolved = TrainingHarnessPolicy.taskSolved(result: result)
                let harnessSatisfied = harnessPolicySatisfied(result: result)
                let gateReport = TrainingHarnessPolicy.report(
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

    private func harnessPolicySatisfied(result: TrainingProbeResult) -> Bool {
        TrainingHarnessPolicy.satisfied(result: result)
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

    @Option(help: "Model descriptor path.")
    var model: String = ""

    @Option(name: .customLong("artifact-root"), help: "Directory where sweep artifacts are written.")
    var artifactRootPath: String?

    @Option(name: .customLong("source-checkpoint"), help: "Optional source checkpoint directory to continue probe attempts from.")
    var sourceCheckpointPath: String?

    @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
    var sequenceLength: Int = 8

    @Option(name: .customLong("epochs"), help: "Epochs for each supervised ManasMLX probe.")
    var epochs: Int = 50

    @Option(name: .customLong("lr"), help: "Learning rate for each supervised ManasMLX probe.")
    var learningRate: Double = 0.0001

    @Option(name: .customLong("max-batches"), help: "Maximum training batches for each supervised ManasMLX probe.")
    var maxBatches: Int = 35

    @Option(help: "Number of seed bases to evaluate.")
    var seeds: Int = 5

    @Option(help: "Comma-separated task list: lift,singleLift. Defaults to singleLift.")
    var tasks: String = "singleLift"

    @Option(help: "Maximum probe attempts per seed. Each attempt increments the seed.")
    var attempts: Int = 3

    @Option(name: .customLong("recovery-repeat"), help: "Repeat recovery relabel datasets this many times when mixing retry training data.")
    var recoveryRepeat: Int = 3

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
        let descriptor = try loadDescriptor(modelPath: model)
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

        let environmentReport = try await KuyuEnvironmentReadinessChecker().check(
            tasks: selectedTaskModes,
            controller: .teacherBaseline,
            parameters: parameters,
            schedule: schedule,
            determinism: determinism,
            gains: gains,
            modelDescriptorPath: model,
            descriptor: descriptor,
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
                    let repairSourceCheckpointURL = repairSourceCheckpointURL(from: result)
                    currentSourceCheckpointURL = repairSourceCheckpointURL
                    if let recoveryDatasetURL = acceptedRecoveryDatasetURL(from: result) {
                        recoveryDatasetURLs.append(recoveryDatasetURL)
                    }
                    let artifacts = try TrainingProbeArtifactValidator().loadAndValidate(from: attemptRoot)
                    let taskSolved = TrainingHarnessPolicy.taskSolved(result: result)
                    let harnessSatisfied = TrainingHarnessPolicy.satisfied(result: result)
                    let preRegressionGateReport = TrainingHarnessPolicy.report(
                        result: result,
                        requireTaskSolved: requireTaskSolved,
                        postRegression: nil
                    )
                    let accepted = preRegressionGateReport.accepted
                    let postRegressionEntry: KuyuPostTrainingRegressionEntry?
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
                            let validatedRegression = try KuyuRegressionArtifactValidator()
                                .loadAndValidate(from: regressionRoot)
                            postRegressionEntry = makePostTrainingRegressionEntry(
                                regression: validatedRegression,
                                artifactPath: regressionRoot.path,
                                minimumRewardAverage: validatedRegression.gateReport.minimumRewardAverage
                            )
                            print("[harness-sweep] seed=\(seedBase) task=\(task.rawValue) attempt=\(attempt) postRegression=\(validatedRegression.allPassed)")
                        } else {
                            let defaultMinimumRewardAverage = KuyuRegressionQualityGatePolicy
                                .defaultMinimumRewardAverage(for: task.rawValue)
                            postRegressionEntry = KuyuPostTrainingRegressionEntry(
                                attempted: false,
                                applicable: true,
                                artifactPath: nil,
                                allPassed: false,
                                failureReasons: ["missing-checkpoint-url"],
                                rewardAverageMinimum: postRegressionMinRewardAverage ?? defaultMinimumRewardAverage,
                                worstRewardAverage: nil,
                                rewardAverageSatisfied: (postRegressionMinRewardAverage ?? defaultMinimumRewardAverage) == nil,
                                qualityTask: task.rawValue,
                                taskPassRate: nil,
                                achievedHoldTime: nil,
                                requiredHoldTime: nil,
                                maxAltitudeErrorAfterWarmup: nil,
                                tolerance: nil,
                                primaryRejectReason: "missing-checkpoint-url"
                            )
                        }
                    } else {
                        postRegressionEntry = nil
                    }
                    let gateReport = TrainingHarnessPolicy.report(
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

    @Option(help: "Controller to validate: teacherBaseline, sensorBaseline, or manasMLX.")
    var controller: ControllerChoice = .teacherBaseline

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

    @Option(help: "Model descriptor path.")
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
        let validatedSummary = try KuyuRegressionArtifactValidator().loadAndValidate(from: artifactRoot)
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
        return try values.map { value in
            guard let suite = Int(value), [6, 7, 8].contains(suite) else {
                throw ValidationError("--suites only supports 6, 7, and 8.")
            }
            return suite
        }
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

    private func writeRegressionSummary(_ summary: KuyuRegressionSummary, to artifactRoot: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(summary).write(
            to: artifactRoot.appendingPathComponent("kuyu-regression-summary.json"),
            options: [.atomic]
        )
    }
}

struct CheckKuyuRegressionMatrix: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check-kuyu-regression-matrix",
        abstract: "Run a task/controller matrix of Kuyu regression checks."
    )

    @Option(help: "Comma-separated controller list: teacherBaseline,sensorBaseline,manasMLX.")
    var controllers: String = "teacherBaseline"

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

    @Option(help: "Model descriptor path.")
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
                    let summary = try KuyuRegressionArtifactValidator().loadAndValidate(from: cellRoot)
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

@MainActor
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
) async throws -> KuyuRegressionSummary {
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)

    let environmentController: ControllerSelection = selectedController.isBaselineController
        ? selectedController
        : .teacherBaseline
    let snapshotPath = snapshotURL?.path
    let regressionTask = regressionRolloutTask(selectedTasks)
    let effectiveMinimumRewardAverage = KuyuRegressionQualityGatePolicy.minimumRewardAverage(
        override: minimumRewardAverage,
        task: regressionTask.rawValue
    )

    if selectedController == .manasMLX {
        do {
            _ = try ManasMLXE2EPreflight().check(
                descriptorPath: model,
                sourceCheckpointURL: snapshotURL,
                requireSourceCheckpoint: true
            )
        } catch {
            let gateReport = KuyuRegressionGatePolicy.report(
                preflightFailure: String(describing: error),
                environmentTasks: [],
                rolloutSuites: [],
                failOnTruncation: failOnTruncation,
                minimumRewardAverage: effectiveMinimumRewardAverage,
                qualityGateTask: regressionTask.rawValue
            )
            let summary = KuyuRegressionSummary(
                schemaVersion: KuyuRegressionSummary.currentSchemaVersion,
                artifactRoot: artifactRoot.path,
                startedAt: Date(),
                controller: selectedController.rawValue,
                environmentController: environmentController.rawValue,
                snapshot: snapshotPath,
                preflightPassed: false,
                preflightFailure: String(describing: error),
                environmentReady: false,
                environmentTasks: [],
                rolloutPassed: false,
                rolloutSuites: [],
                gateReport: gateReport,
                allPassed: gateReport.accepted
            )
            try writeKuyuRegressionSummary(summary, to: artifactRoot)
            return summary
        }
    }

    let determinism = try makeDeterminism(tier: tier)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
    let descriptor = try loadDescriptor(modelPath: model)
    let loadedDescriptor = try loadLoadedDescriptor(modelPath: model)
    let parameters = try makeRolloutParameters(task: regressionTask, loadedDescriptor: loadedDescriptor)
    let gains = try ImuRateDampingCutGains(
        kp: kp,
        kd: kd,
        yawDamping: yawDamping,
        hoverThrustScale: hoverScale
    )

    let environmentRoot = artifactRoot.appendingPathComponent("environment-readiness", isDirectory: true)
    let environmentReport = try await KuyuEnvironmentReadinessChecker().check(
        tasks: selectedTasks,
        controller: environmentController,
        parameters: parameters,
        schedule: schedule,
        determinism: determinism,
        gains: gains,
        modelDescriptorPath: model,
        descriptor: descriptor,
        artifactRoot: environmentRoot
    )

    if
        selectedController == .manasMLX,
        let snapshotURL,
        let compatibilityFailure = try regressionSnapshotCompatibilityFailure(snapshotURL: snapshotURL)
    {
        let rolloutEntries = selectedSuites.map { suite in
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
            failOnTruncation: failOnTruncation,
            minimumRewardAverage: effectiveMinimumRewardAverage,
            qualityGateTask: regressionTask.rawValue
        )
        let summary = KuyuRegressionSummary(
            schemaVersion: KuyuRegressionSummary.currentSchemaVersion,
            artifactRoot: artifactRoot.path,
            startedAt: Date(),
            controller: selectedController.rawValue,
            environmentController: environmentController.rawValue,
            snapshot: snapshotPath,
            preflightPassed: true,
            preflightFailure: nil,
            environmentReady: environmentReport.allReady,
            environmentTasks: environmentReport.tasks,
            rolloutPassed: false,
            rolloutSuites: rolloutEntries,
            gateReport: gateReport,
            allPassed: gateReport.accepted
        )
        try writeKuyuRegressionSummary(summary, to: artifactRoot)
        print("[regression] skipped rollout reason=\(compatibilityFailure)")
        return summary
    }

    var rolloutEntries: [KuyuRegressionRolloutEntry] = []
    for suite in selectedSuites {
        let definitions = try makeRegressionRolloutDefinitions(
            task: regressionTask,
            suite: suite,
            episodes: episodes
        )
        let track = regressionTrackName(for: suite)
        let runner = RolloutRunner(
            parameters: parameters,
            schedule: schedule,
            determinism: determinism,
            hoverThrustScale: hoverScale,
            loadedDescriptor: loadedDescriptor,
            motorNerveRateLimitPerSecond: selectedController == .teacherBaseline ? 100.0 : 2.0,
            motorNerveSmoothingTimeConstant: selectedController == .teacherBaseline ? nil : 0.08,
            limits: try RolloutRunner.Limits.validated(
                maxStepsPerEpisode: maxSteps,
                maxWallTimeSeconds: maxWallTime
            )
        )
        let policyFactory = try makeRegressionPolicyFactory(
            controller: selectedController,
            snapshotURL: snapshotURL,
            parameters: parameters,
            gains: gains,
            useQualityGating: useQualityGating
        )

        do {
            let episodesOut: [RolloutEpisode]
            if workers == 1 {
                episodesOut = try await runner.run(definitions: definitions, policyFactory: policyFactory)
            } else {
                let collector = try ParallelRolloutCollector(runner: runner, workerCount: workers)
                episodesOut = try await collector.collect(definitions: definitions, policyFactory: policyFactory)
            }

            let summary = RolloutSummary(episodes: episodesOut)
            let rewardAverage = summary.episodeCount > 0 ? summary.rewardSum / Double(summary.episodeCount) : 0
            let taskEvaluation = evaluateRegressionEpisodes(
                definitions: definitions,
                episodes: episodesOut,
                determinism: determinism
            )
            let entry = KuyuRegressionRolloutEntry(
                suite: suite,
                track: track,
                policyID: policyFactory.policyID,
                episodeCount: summary.episodeCount,
                rewardSum: summary.rewardSum,
                rewardAverage: rewardAverage,
                doneCount: summary.doneCount,
                truncatedCount: summary.truncatedCount,
                failureCount: summary.failureCount,
                cancelledCount: summary.cancelledCount,
                failureReasons: Array(Set(episodesOut.compactMap(\.failureReason))).sorted(),
                taskPassCount: taskEvaluation.passCount,
                taskFailureCount: taskEvaluation.failureCount,
                taskFailureReasons: taskEvaluation.failureReasons,
                taskQuality: taskEvaluation.taskQuality,
                workerSummaries: regressionWorkerSummaries(
                    episodes: episodesOut,
                    snapshotURL: snapshotURL,
                    rolloutRoot: artifactRoot.appendingPathComponent("rollouts/\(track)", isDirectory: true)
                ),
                artifactPath: nil
            )
            rolloutEntries.append(entry)
            print("[regression] suite=\(suite) track=\(track) episodes=\(entry.episodeCount) workers=\(entry.workerSummaries.count) rewardAvg=\(String(format: "%.3f", rewardAverage)) failures=\(entry.failureCount) taskFailures=\(entry.taskFailureCount) taskPassRate=\(String(format: "%.3f", regressionTaskPassRate(entry))) truncated=\(entry.truncatedCount) \(regressionQualityText(entry.taskQuality)) \(regressionWorkerText(entry.workerSummaries))")
        } catch {
            let entry = KuyuRegressionRolloutEntry(
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
            )
            rolloutEntries.append(entry)
            print("[regression] suite=\(suite) track=\(track) failed reason=\(entry.failureReasons.joined(separator: " | "))")
        }
    }

    let rolloutPassed = rolloutEntries.allSatisfy { entry in
        entry.failureCount == 0
            && entry.cancelledCount == 0
            && entry.taskFailureCount == 0
            && entry.taskPassCount == entry.episodeCount
            && (!failOnTruncation || entry.truncatedCount == 0)
    }
    let gateReport = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: environmentReport.tasks,
        rolloutSuites: rolloutEntries,
        failOnTruncation: failOnTruncation,
        minimumRewardAverage: effectiveMinimumRewardAverage,
        qualityGateTask: regressionTask.rawValue
    )
    let summary = KuyuRegressionSummary(
        schemaVersion: KuyuRegressionSummary.currentSchemaVersion,
        artifactRoot: artifactRoot.path,
        startedAt: Date(),
        controller: selectedController.rawValue,
        environmentController: environmentController.rawValue,
        snapshot: snapshotPath,
        preflightPassed: true,
        preflightFailure: nil,
        environmentReady: environmentReport.allReady,
        environmentTasks: environmentReport.tasks,
        rolloutPassed: rolloutPassed,
        rolloutSuites: rolloutEntries,
        gateReport: gateReport,
        allPassed: gateReport.accepted
    )
    try writeKuyuRegressionSummary(summary, to: artifactRoot)
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

private func makeRegressionPolicyFactory(
    controller selectedController: ControllerSelection,
    snapshotURL: URL?,
    parameters: ReferenceQuadrotorParameters,
    gains: ImuRateDampingCutGains,
    useQualityGating: Bool
) throws -> any ReferenceQuadrotorPolicyFactory {
    switch selectedController {
    case .baseline, .teacherBaseline:
        return KuyAtt1BaselinePolicyFactory(
            parameters: parameters,
            gains: gains,
            mode: .teacher
        )
    case .sensorBaseline:
        return KuyAtt1BaselinePolicyFactory(
            parameters: parameters,
            gains: gains,
            mode: .sensor
        )
    case .manasMLX:
        guard let snapshotURL else {
            throw ValidationError("--snapshot is required when --controller manasMLX.")
        }
        return ManasMLXRolloutPolicyFactory(
            snapshotDirectory: snapshotURL,
            policyID: "manasMLX-regression",
            useQualityGating: useQualityGating
        )
    }
}

private func regressionSnapshotCompatibilityFailure(snapshotURL: URL) throws -> String? {
    try ManasMLXCheckpointCompatibility(expectedDriveCount: 4)
        .validate(snapshotURL: snapshotURL)?
        .description
}

private func parseRegressionSuites(_ raw: String) throws -> [Int] {
    let values = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !values.isEmpty else {
        throw ValidationError("--suites must include at least one suite.")
    }
    return try values.map { value in
        guard let suite = Int(value), [6, 7, 8].contains(suite) else {
            throw ValidationError("--suites only supports 6, 7, and 8.")
        }
        return suite
    }
}

private struct RegressionTaskEvaluation {
    let passCount: Int
    let failureCount: Int
    let failureReasons: [String]
    let taskQuality: [ReferenceQuadrotorTaskQualitySummary]
}

private func evaluateRegressionEpisodes(
    definitions: [ReferenceQuadrotorScenarioDefinition],
    episodes: [RolloutEpisode],
    determinism: DeterminismConfig
) -> RegressionTaskEvaluation {
    let definitionByKey = Dictionary(
        uniqueKeysWithValues: definitions.map {
            (rolloutDefinitionKey(scenarioId: $0.config.id.rawValue, seed: $0.config.seed.rawValue), $0)
        }
    )
    let evaluator = ReferenceQuadrotorScenarioEvaluator()
    let qualityEvaluator = ReferenceQuadrotorTaskQualityEvaluator()
    var passCount = 0
    var failureReasons: [String] = []
    var taskQuality: [ReferenceQuadrotorTaskQualitySummary] = []

    for episode in episodes {
        guard let definition = definitionByKey[rolloutDefinitionKey(scenarioId: episode.scenarioId, seed: episode.seed)] else {
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

    let uniqueReasons = Array(Set(failureReasons)).sorted()
    return RegressionTaskEvaluation(
        passCount: passCount,
        failureCount: episodes.count - passCount,
        failureReasons: uniqueReasons,
        taskQuality: taskQuality
    )
}

private func regressionTaskPassRate(_ entry: KuyuRegressionRolloutEntry) -> Double {
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

private func regressionWorkerSummaries(
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

private func regressionWorkerText(_ summaries: [KuyuRegressionWorkerSummary]) -> String {
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

private func regressionFailureReasons(from summary: KuyuRegressionSummary) -> [String] {
    var reasons: [String] = []
    if let preflightFailure = summary.preflightFailure {
        reasons.append(preflightFailure)
    }
    reasons.append(contentsOf: summary.environmentTasks.filter { !$0.ready }.map { "environment:\($0.task)" })
    reasons.append(contentsOf: summary.rolloutSuites.flatMap(\.failureReasons))
    reasons.append(contentsOf: summary.rolloutSuites.flatMap(\.taskFailureReasons))
    reasons.append(contentsOf: summary.gateReport.reasons)
    return Array(Set(reasons)).sorted()
}

private func postRegressionApplicable(_ summary: KuyuRegressionSummary) -> Bool {
    let reasons = regressionFailureReasons(from: summary)
    guard !reasons.isEmpty else {
        return true
    }
    return !reasons.allSatisfy { $0.contains("incompatible-checkpoint-drive-count") }
}

private func makePostTrainingRegressionEntry(
    regression: KuyuRegressionSummary,
    artifactPath: String,
    minimumRewardAverage: Double?
) -> KuyuPostTrainingRegressionEntry {
    let rewardAverageSatisfied: Bool
    let rewardFailureReasons: [String]
    if let minimumRewardAverage {
        if regression.rolloutSuites.isEmpty {
            rewardAverageSatisfied = false
            rewardFailureReasons = ["post-regression-reward-average-missing"]
        } else {
            let failures = regression.rolloutSuites
                .filter { $0.rewardAverage < minimumRewardAverage }
                .map { entry in
                    "post-regression-reward-average-below-min:\(entry.track):\(entry.rewardAverage)<\(minimumRewardAverage)"
                }
            rewardAverageSatisfied = failures.isEmpty
            rewardFailureReasons = failures
        }
    } else {
        rewardAverageSatisfied = true
        rewardFailureReasons = []
    }
    let failureReasons = regressionFailureReasons(from: regression) + rewardFailureReasons
    let firstEntry = regression.rolloutSuites.first
    let firstQuality = firstEntry?.taskQuality.first
    let taskPassRate = firstEntry.flatMap { entry -> Double? in
        guard entry.episodeCount > 0 else { return nil }
        return Double(entry.taskPassCount) / Double(entry.episodeCount)
    }
    return KuyuPostTrainingRegressionEntry(
        attempted: true,
        applicable: postRegressionApplicable(regression),
        artifactPath: artifactPath,
        allPassed: regression.allPassed && rewardAverageSatisfied,
        failureReasons: failureReasons,
        rewardAverageMinimum: minimumRewardAverage,
        worstRewardAverage: regression.rolloutSuites.map(\.rewardAverage).min(),
        rewardAverageSatisfied: rewardAverageSatisfied,
        qualityTask: regression.gateReport.qualityGateTask,
        taskPassRate: taskPassRate,
        achievedHoldTime: firstQuality?.achievedHoldTime,
        requiredHoldTime: firstQuality?.requiredHoldTime,
        maxAltitudeErrorAfterWarmup: firstQuality?.maxAltitudeErrorAfterWarmup,
        tolerance: firstQuality?.tolerance,
        primaryRejectReason: failureReasons.first
    )
}

private func postRegressionAcceptanceSatisfied(_ entry: KuyuPostTrainingRegressionEntry?) -> Bool {
    guard let entry else {
        return true
    }
    return !entry.applicable || entry.allPassed
}

private func writeKuyuRegressionSummary(_ summary: KuyuRegressionSummary, to artifactRoot: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(summary).write(
        to: artifactRoot.appendingPathComponent("kuyu-regression-summary.json"),
        options: [.atomic]
    )
    _ = try KuyuRegressionArtifactValidator().loadAndValidate(from: artifactRoot)
}

private enum TrainingHarnessPolicy {
    static func report(
        result: TrainingProbeResult,
        requireTaskSolved: Bool,
        postRegression: KuyuPostTrainingRegressionEntry?
    ) -> TrainingHarnessGateReport {
        var reasons = requireTaskSolved
            ? taskSolvedRejectionReasons(result: result)
            : harnessRejectionReasons(result: result)
        if let postRegression, !postRegressionAcceptanceSatisfied(postRegression) {
            reasons.append("post-regression-failed")
            reasons.append(contentsOf: postRegression.failureReasons.map { "post-regression:\($0)" })
        }
        return TrainingHarnessGateReport(
            requirement: requirementName(requireTaskSolved: requireTaskSolved, postRegression: postRegression != nil),
            accepted: reasons.isEmpty,
            reasons: reasons
        )
    }

    static func taskSolved(result: TrainingProbeResult) -> Bool {
        taskSolvedRejectionReasons(result: result).isEmpty
    }

    static func satisfied(result: TrainingProbeResult) -> Bool {
        harnessRejectionReasons(result: result).isEmpty
    }

    private static func taskSolvedRejectionReasons(result: TrainingProbeResult) -> [String] {
        var reasons: [String] = []
        if result.manifest.terminalState != .completed {
            reasons.append("terminal-not-completed:\(result.manifest.terminalState.rawValue)")
        }
        if result.probeCheckpointDecision.state != .accepted {
            reasons.append("probe-checkpoint-not-accepted:\(result.probeCheckpointDecision.state.rawValue)")
        }
        if !result.comparison.reloadSucceeded {
            reasons.append("reload-failed")
        }
        if !result.comparison.policySatisfied {
            reasons.append("policy-not-satisfied")
        }
        reasons.append(contentsOf: result.comparison.probeRejectionReasons.map { "probe:\($0)" })
        return Array(Set(reasons)).sorted()
    }

    private static func harnessRejectionReasons(result: TrainingProbeResult) -> [String] {
        var reasons: [String] = []
        if !result.training.convergence.accepted {
            reasons.append("convergence-rejected:\(result.training.convergence.reason)")
        }
        if result.comparison.checkpointDecision != .accepted && result.comparison.checkpointDecision != .staged {
            reasons.append("checkpoint-not-accepted:\(result.comparison.checkpointDecision.rawValue)")
        }
        if result.comparison.selectedCheckpointRole != .candidate {
            reasons.append("selected-checkpoint-not-candidate:\(result.comparison.selectedCheckpointRole.rawValue)")
        }
        if result.comparison.selectedCheckpointURL == nil {
            reasons.append("missing-selected-checkpoint")
        }
        if !result.comparison.reloadSucceeded {
            reasons.append("reload-failed")
        }
        if !result.comparison.referenceSatisfied {
            reasons.append("reference-not-satisfied")
        }
        if !result.comparison.meetsMinimumDelta {
            reasons.append("minimum-delta-not-met")
        }
        if !result.comparison.safetyNonRegression {
            reasons.append("safety-regression")
        }
        if !result.comparison.teacherDivergenceNonRegression {
            reasons.append("teacher-divergence-regression")
        }
        guard let trained = result.trained else {
            reasons.append("missing-trained-run")
            return Array(Set(reasons)).sorted()
        }
        reasons.append(contentsOf: hardSafetyFailures(trained.diagnostics.failureReasons).map { "hard-safety-failure:\($0)" })
        if !driveActivationCloseEnough(teacher: result.teacher, trained: trained) {
            reasons.append("drive-activation-diverged")
        }
        if !altitudeSmokeSatisfied(trained: trained) {
            reasons.append("altitude-smoke-failed")
        }
        if (result.comparison.scoreDelta ?? -Double.greatestFiniteMagnitude) < 0 {
            reasons.append("negative-score-delta")
        }
        return Array(Set(reasons)).sorted()
    }

    private static func requirementName(requireTaskSolved: Bool, postRegression: Bool) -> String {
        let base = requireTaskSolved ? "taskSolved" : "harnessSatisfied"
        return postRegression ? "\(base)+postRegression" : base
    }

    private static func hasHardSafetyFailure(_ reasons: [String]) -> Bool {
        !hardSafetyFailures(reasons).isEmpty
    }

    private static func hardSafetyFailures(_ reasons: [String]) -> [String] {
        let hardFailures: Set<String> = ["ground-violation", "sustained-fall", "sustained-violation"]
        return reasons.filter { hardFailures.contains($0) }.sorted()
    }

    private static func driveActivationCloseEnough(
        teacher: TrainingProbeRunSummary,
        trained: TrainingProbeRunSummary
    ) -> Bool {
        guard
            let teacherAverage = teacher.diagnostics.averageDriveActivation,
            let trainedAverage = trained.diagnostics.averageDriveActivation
        else {
            return false
        }
        return abs(teacherAverage - trainedAverage) <= 0.05
    }

    private static func altitudeSmokeSatisfied(trained: TrainingProbeRunSummary) -> Bool {
        guard
            let minAltitude = trained.diagnostics.minAltitudeZ,
            let finalAltitude = trained.diagnostics.finalAltitudeZ
        else {
            return false
        }
        return minAltitude >= 0.25 && finalAltitude >= 0.25
    }
}

private func selectedCandidateCheckpointURL(_ comparison: TrainingProbeComparison) -> URL? {
    guard comparison.selectedCheckpointRole == .candidate else {
        return nil
    }
    return comparison.selectedCheckpointURL
}

private func repairSourceCheckpointURL(from result: TrainingProbeResult) -> URL? {
    if let selected = result.comparison.selectedCheckpointURL {
        return selected
    }
    guard result.comparison.policySatisfied,
          result.comparison.trainedPassed == true,
          !result.comparison.teacherDivergenceNonRegression
    else {
        return nil
    }
    return result.training.checkpointDecision.candidateCheckpointURL
}

private func acceptedRecoveryDatasetURL(from result: TrainingProbeResult) -> URL? {
    guard result.recoveryRelabelStatus.attempted else {
        return nil
    }
    guard result.recoveryRelabelStatus.failureReason == nil else {
        return nil
    }
    guard let report = result.recoveryRelabelStatus.report, report.relabeledEntryCount > 0 else {
        return nil
    }
    return result.recoveryRelabelStatus.datasetDirectory
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
    let allPassed: Bool
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

private struct TrainingHarnessGateReport: Codable {
    let requirement: String
    let accepted: Bool
    let reasons: [String]
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
    let postRegression: KuyuPostTrainingRegressionEntry?
}

private struct KuyuPostTrainingRegressionEntry: Codable {
    let attempted: Bool
    let applicable: Bool
    let artifactPath: String?
    let allPassed: Bool
    let failureReasons: [String]
    let rewardAverageMinimum: Double?
    let worstRewardAverage: Double?
    let rewardAverageSatisfied: Bool
    let qualityTask: String?
    let taskPassRate: Double?
    let achievedHoldTime: Double?
    let requiredHoldTime: Double?
    let maxAltitudeErrorAfterWarmup: Double?
    let tolerance: Double?
    let primaryRejectReason: String?
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
    let preflight = try ManasMLXE2EPreflight().check(
        descriptorPath: model,
        sourceCheckpointURL: sourceCheckpointURL
    )
    if printEvents {
        print("[probe] preflight mlx=\(preflight.mlxRuntimeReady) descriptorLoaded=\(preflight.descriptorLoaded) sourceCheckpointLoadable=\(preflight.sourceCheckpointLoadable)")
        if !additionalDatasetURLs.isEmpty {
            print("[probe] additionalDatasets=\(additionalDatasetURLs.map(\.path).joined(separator: ","))")
        }
    }

    let determinism = try makeDeterminism(tier: tier)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
    let parameters = try loadParameters(modelPath: model)
    let descriptor = try loadDescriptor(modelPath: model)
    let gains = try ImuRateDampingCutGains(
        kp: kp,
        kd: kd,
        yawDamping: yawDamping,
        hoverThrustScale: hoverScale
    )
    let taskMode = simulationTaskMode(from: task)
    let runID = "probe-\(UUID().uuidString)"
    let teacherRequest = SimulationRunRequest(
        controller: .teacherBaseline,
        taskMode: taskMode,
        gains: gains,
        cutPeriodSteps: cutPeriodSteps,
        noise: .zero,
        determinism: determinism,
        modelDescriptorPath: model,
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
        modelDescriptorPath: model,
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
            descriptorID: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : model,
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
                descriptorID: sourceSnapshot?.descriptorID,
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
            .appendingPathComponent("candidate-checkpoints", isDirectory: true)
    )
    let probe = TrainingProbeOrchestrator(
        scenarioExecutor: CLITrainingProbeExecutor(
            teacherRequest: teacherRequest,
            initialStore: initialStore,
            trainedStore: trainedStore,
            parameters: parameters,
            schedule: schedule,
            descriptor: descriptor
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
private struct CLIScenarioExecutor: TrainingScenarioExecuting {
    let store: ManasMLXModelStore
    let parameters: ReferenceQuadrotorParameters
    let schedule: SimulationSchedule
    let descriptor: RobotDescriptor?

    func runSuiteForTrainingRun(request: SimulationRunRequest) async throws -> KuyAtt1RunOutput {
        try await store.runManasMLX(
            parameters: parameters,
            schedule: schedule,
            request: request,
            descriptor: descriptor,
            control: nil
        )
    }
}

@MainActor
private final class CLITrainingProbeExecutor: TrainingProbeScenarioExecuting {
    private let teacherRequest: SimulationRunRequest
    private let initialStore: ManasMLXModelStore
    private let trainedStore: ManasMLXModelStore
    private let parameters: ReferenceQuadrotorParameters
    private let schedule: SimulationSchedule
    private let descriptor: RobotDescriptor?

    init(
        teacherRequest: SimulationRunRequest,
        initialStore: ManasMLXModelStore,
        trainedStore: ManasMLXModelStore,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        descriptor: RobotDescriptor?
    ) {
        self.teacherRequest = teacherRequest
        self.initialStore = initialStore
        self.trainedStore = trainedStore
        self.parameters = parameters
        self.schedule = schedule
        self.descriptor = descriptor
    }

    func runProbeSuite(
        stage: TrainingProbeStage,
        request: SimulationRunRequest,
        checkpointURL: URL?
    ) async throws -> KuyAtt1RunOutput {
        switch stage {
        case .teacherBaseline:
            return try await KuyuScenarioRuntime(modelStore: initialStore).run(
                request: teacherRequest,
                parameters: parameters,
                schedule: schedule,
                descriptor: descriptor,
                control: nil
            )
        case .trainingIteration:
            if teacherRequest.taskMode == .singleLift {
                return try await KuyuSingleLiftTeacherDatasetRunner().run(
                    request: teacherRequest,
                    parameters: parameters,
                    schedule: schedule,
                    control: nil
                )
            }
            return try await KuyuScenarioRuntime(modelStore: initialStore).run(
                request: teacherRequest,
                parameters: parameters,
                schedule: schedule,
                descriptor: descriptor,
                control: nil
            )
        case .initialPolicy:
            return try await initialStore.runManasMLX(
                parameters: parameters,
                schedule: schedule,
                request: request,
                descriptor: descriptor,
                control: nil
            )
        case .trainedPolicy:
            guard let checkpointURL else {
                throw ValidationError("Accepted checkpoint URL is required before trained probe run.")
            }
            _ = try trainedStore.loadModel(from: checkpointURL)
            return try await trainedStore.runManasMLX(
                parameters: parameters,
                schedule: schedule,
                request: request,
                descriptor: descriptor,
                control: nil
            )
        }
    }

    func writeRecoveryRelabelDataset(
        output: KuyAtt1RunOutput,
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
    var population: Int = 4

    @Option(help: "Number of generations.")
    var generations: Int = 1

    @Option(name: .customLong("elite-count"), help: "Number of candidates selected as parents.")
    var eliteCount: Int = 1

    @Option(help: "Worker count for rollout regression.")
    var workers: Int = 1

    @Option(name: .customLong("candidate-evaluation-concurrency"), help: "Maximum Manas candidate evaluations to run concurrently.")
    var candidateEvaluationConcurrency: Int = 1

    @Option(help: "Comma-separated M2 suite list: 6,7,8.")
    var suites: String = "6"

    @Option(help: "Episodes per candidate regression.")
    var episodes: Int = 1

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Model descriptor path.")
    var model: String = ""

    @Option(name: .customLong("artifact-root"), help: "Directory where evolution artifacts are written.")
    var artifactRootPath: String?

    @Option(name: .customLong("mutation-rate"), help: "Mutation rate passed to the ManasMLX variation provider.")
    var mutationRate: Double = 0.08

    @Option(name: .customLong("mutation-noise-scale"), help: "Gaussian mutation noise scale.")
    var mutationNoiseScale: Double = 0.01

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

    @Flag(name: .customLong("adaptive-mutation"), help: "Adapt mutation rate and noise scale based on generation gate results.")
    var adaptiveMutation: Bool = false

    @Option(help: "Candidate variation mode: gaussian or copy.")
    var variation: EvolutionVariationChoice = .gaussian

    @Option(help: "Candidate evaluation mode: regression or candidateOnly.")
    var evaluation: EvolutionEvaluationChoice = .regression

    @Flag(name: .customLong("no-crossover"), help: "Disable elite checkpoint averaging before mutation.")
    var noCrossover: Bool = false

    @Option(name: .customLong("min-reward-average"), help: "Override task default minimum reward average.")
    var minimumRewardAverage: Double?

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
        let taskMode = simulationTaskMode(from: task)
        let backend = ManasMLXEvolutionBackend(
            rootDirectory: artifactRoot.appendingPathComponent("candidates", isDirectory: true),
            variationProvider: makeVariationProvider()
        )
        let evaluator: any EvolutionCandidateEvaluating
        switch evaluation {
        case .regression:
            evaluator = CLIEvolutionRegressionEvaluator(
                task: taskMode,
                tier: tier,
                cutPeriodSteps: cutPeriodSteps,
                suites: selectedSuites,
                episodes: episodes,
                workers: workers,
                model: model,
                artifactRoot: artifactRoot.appendingPathComponent("candidate-evaluations", isDirectory: true),
                minimumRewardAverage: minimumRewardAverage,
                useQualityGating: !noQualityGate
            )
        case .candidateOnly:
            evaluator = CLICandidateOnlyEvolutionEvaluator(task: task.rawValue)
        }
        let orchestrator = EvolutionRunOrchestrator(
            backend: backend,
            evaluator: evaluator
        )
        let result = await orchestrator.run(
            config: EvolutionRunConfig(
                taskID: task.rawValue,
                descriptorID: model.isEmpty ? nil : model,
                descriptorHash: model.isEmpty ? nil : model,
                configHash: "\(task.rawValue)-\(suites)-\(episodes)-\(workers)-\(candidateEvaluationConcurrency)-\(searchStrategy.rawValue)",
                policyID: "manasMLX",
                populationSize: population,
                generationCount: generations,
                eliteCount: eliteCount,
                workerCount: workers,
                candidateEvaluationConcurrency: candidateEvaluationConcurrency,
                searchStrategy: searchStrategy.trainingStrategy,
                bootstrapSource: bootstrapSource.trainingSource,
                worldModelUsage: worldModelUsage.trainingUsage,
                antitheticSampling: antitheticSampling,
                commonRandomSeed: commonRandomSeed,
                mutationRate: mutationRate,
                mutationNoiseScale: mutationNoiseScale,
                adaptiveMutation: EvolutionAdaptiveMutationConfig(enabled: adaptiveMutation),
                parentCheckpointID: snapshotURL.lastPathComponent,
                parentCheckpointURL: snapshotURL
            ),
            gatePolicy: EvolutionGatePolicy(
                eliteCount: eliteCount,
                minimumTaskPassRate: 1.0,
                maximumSafetyViolationRate: 0,
                minimumHoldTimeRatio: task == .lift || task == .singleLift ? 1.0 : nil,
                minimumRewardAverage: minimumRewardAverage
            ),
            artifactDirectory: artifactRoot
        )
        let artifacts = try EvolutionRunArtifactValidator().loadAndValidate(from: artifactRoot)
        print("[evolve] artifacts path=\(artifactRoot.path)")
        print("[evolve] terminal=\(artifacts.manifest.terminalState.rawValue) variation=\(variation.rawValue) evaluation=\(evaluation.rawValue) generations=\(artifacts.generations.count) candidates=\(artifacts.candidates.count) best=\(artifacts.eliteArchive.bestCandidateID ?? "n/a") bestFitness=\(formatOptional(artifacts.eliteArchive.bestFitness)) elites=\(artifacts.eliteArchive.eliteCandidateIDs.joined(separator: ","))")
        printEvolutionSearchSummary(artifacts: artifacts, adaptiveMutation: adaptiveMutation)
        if result.manifest.terminalState != .completed {
            throw ExitCode.failure
        }
    }

    private func printEvolutionSearchSummary(
        artifacts: EvolutionRunArtifactBundle,
        adaptiveMutation: Bool
    ) {
        let manifest = artifacts.manifest
        let finalGeneration = artifacts.generations.last
        let bestQDCell = artifacts.qualityDiversityArchive.cells.max { lhs, rhs in
            if lhs.fitness == rhs.fitness {
                return lhs.candidateID > rhs.candidateID
            }
            return lhs.fitness < rhs.fitness
        }
        print(
            "[evolve] strategy=\(manifest.searchStrategy.rawValue) bootstrap=\(manifest.bootstrapSource.rawValue) worldModel=\(manifest.worldModelUsage.rawValue) antithetic=\(manifest.antitheticSampling) commonSeed=\(manifest.commonRandomSeed) adaptiveMutation=\(adaptiveMutation)"
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
        let requiresMLXCheckpoint = variation == .gaussian || evaluation == .regression
        if requiresMLXCheckpoint {
            let preflight = try ManasMLXE2EPreflight().check(
                descriptorPath: model,
                sourceCheckpointURL: snapshotURL,
                requireSourceCheckpoint: true
            )
            print("[evolve] preflight mlx=\(preflight.mlxRuntimeReady) descriptorLoaded=\(preflight.descriptorLoaded) sourceCheckpointLoadable=\(preflight.sourceCheckpointLoadable)")
        } else {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: snapshotURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw ValidationError("--snapshot must point to an existing checkpoint directory.")
            }
            print("[evolve] preflight mode=lightweight sourceDirectory=true")
        }
    }
}

@MainActor
private final class CLIEvolutionRegressionEvaluator: EvolutionCandidateEvaluating {
    private let task: SimulationTaskMode
    private let tier: TierChoice
    private let cutPeriodSteps: UInt64
    private let suites: [Int]
    private let episodes: Int
    private let workers: Int
    private let model: String
    private let artifactRoot: URL
    private let minimumRewardAverage: Double?
    private let useQualityGating: Bool

    init(
        task: SimulationTaskMode,
        tier: TierChoice,
        cutPeriodSteps: UInt64,
        suites: [Int],
        episodes: Int,
        workers: Int,
        model: String,
        artifactRoot: URL,
        minimumRewardAverage: Double?,
        useQualityGating: Bool
    ) {
        self.task = task
        self.tier = tier
        self.cutPeriodSteps = cutPeriodSteps
        self.suites = suites
        self.episodes = episodes
        self.workers = workers
        self.model = model
        self.artifactRoot = artifactRoot
        self.minimumRewardAverage = minimumRewardAverage
        self.useQualityGating = useQualityGating
    }

    func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary {
        guard let checkpointURL = request.candidate.checkpointURL else {
            return failedFitness(
                request: request,
                reason: "missing-candidate-checkpoint"
            )
        }
        let candidateRoot = artifactRoot
            .appendingPathComponent("generation-\(request.candidate.generationIndex)", isDirectory: true)
            .appendingPathComponent(request.candidate.candidateID, isDirectory: true)
        let summary = try await runKuyuRegression(
            controller: .manasMLX,
            snapshotURL: checkpointURL,
            tier: tier,
            cutPeriodSteps: cutPeriodSteps,
            tasks: [task],
            suites: suites,
            episodes: episodes,
            workers: workers,
            maxSteps: nil,
            maxWallTime: nil,
            model: model,
            artifactRoot: candidateRoot,
            kp: 2.0,
            kd: 0.25,
            yawDamping: 0.2,
            hoverScale: 1.0,
            failOnTruncation: false,
            minimumRewardAverage: minimumRewardAverage,
            useQualityGating: useQualityGating
        )
        return fitness(
            request: request,
            regression: summary
        )
    }

    private func failedFitness(
        request: EvolutionCandidateEvaluationRequest,
        reason: String
    ) -> FitnessSummary {
        FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.candidate.generationIndex,
            candidateID: request.candidate.candidateID,
            taskID: request.config.taskID,
            scalarFitness: -Double.greatestFiniteMagnitude,
            rewardAverage: -Double.greatestFiniteMagnitude,
            taskPassRate: 0,
            safetyViolationRate: 1,
            holdTimeRatio: 0,
            workerThroughput: 0,
            failureReasons: [reason]
        )
    }

    private func fitness(
        request: EvolutionCandidateEvaluationRequest,
        regression: KuyuRegressionSummary
    ) -> FitnessSummary {
        let totalEpisodes = regression.rolloutSuites.reduce(0) { $0 + $1.episodeCount }
        let totalReward = regression.rolloutSuites.reduce(0.0) { $0 + $1.rewardSum }
        let totalPasses = regression.rolloutSuites.reduce(0) { $0 + $1.taskPassCount }
        let totalFailures = regression.rolloutSuites.reduce(0) {
            $0 + $1.failureCount + $1.cancelledCount
        }
        let rewardAverage = totalEpisodes > 0 ? totalReward / Double(totalEpisodes) : 0
        let taskPassRate = totalEpisodes > 0 ? Double(totalPasses) / Double(totalEpisodes) : 0
        let safetyViolationRate = totalEpisodes > 0 ? Double(totalFailures) / Double(totalEpisodes) : 1
        let holdTimeRatio = averageHoldTimeRatio(regression.rolloutSuites)
        let throughput = minimumWorkerThroughput(regression.rolloutSuites)
        let scalarFitness = rewardAverage
            + taskPassRate * 100
            + (holdTimeRatio ?? 0) * 10
            - safetyViolationRate * 100
        return FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.candidate.generationIndex,
            candidateID: request.candidate.candidateID,
            taskID: request.config.taskID,
            scalarFitness: scalarFitness,
            rewardAverage: rewardAverage,
            taskPassRate: taskPassRate,
            safetyViolationRate: safetyViolationRate,
            holdTimeRatio: holdTimeRatio,
            energyPenalty: nil,
            noveltyScore: nil,
            teacherDelta: nil,
            workerThroughput: throughput,
            failureReasons: regression.gateReport.accepted ? [] : regression.gateReport.reasons
        )
    }

    private func averageHoldTimeRatio(_ entries: [KuyuRegressionRolloutEntry]) -> Double? {
        let ratios = entries.flatMap(\.taskQuality).compactMap { quality -> Double? in
            guard let achieved = quality.achievedHoldTime,
                  let required = quality.requiredHoldTime,
                  required > 0 else {
                return nil
            }
            return achieved / required
        }
        guard !ratios.isEmpty else {
            return nil
        }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    private func minimumWorkerThroughput(_ entries: [KuyuRegressionRolloutEntry]) -> Double? {
        let throughputs = entries.flatMap(\.workerSummaries).map(\.throughput)
        return throughputs.min()
    }
}

@MainActor
private final class CLICandidateOnlyEvolutionEvaluator: EvolutionCandidateEvaluating {
    private let task: String

    init(task: String) {
        self.task = task
    }

    func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary {
        let candidateIndex = request.candidate.candidateID
            .split(separator: "c")
            .last
            .flatMap { Int(String($0)) } ?? 0
        let candidateScore = Double(candidateIndex)
        return FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.candidate.generationIndex,
            candidateID: request.candidate.candidateID,
            taskID: task,
            scalarFitness: candidateScore,
            rewardAverage: candidateScore,
            taskPassRate: 1,
            safetyViolationRate: 0,
            holdTimeRatio: 1,
            workerThroughput: Double(request.workerCount),
            failureReasons: []
        )
    }
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
        try MLXRuntimePreflight().check()
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
        try MLXRuntimePreflight().check()
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

private func makeDeterminism(tier: TierChoice) throws -> DeterminismConfig {
    switch tier {
    case .tier0:
        return try DeterminismConfig(tier: .tier0)
    case .tier1:
        return try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
    case .tier2:
        return try DeterminismConfig(tier: .tier2)
    }
}

private func loadParameters(modelPath: String) throws -> ReferenceQuadrotorParameters {
    let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .baseline }

    let loader = RobotDescriptorLoader()
    let descriptor = try loader.loadDescriptor(path: trimmed)
    let inertial = try loader.loadPlantInertialProperties(descriptor: descriptor)
    return try ReferenceQuadrotorParameters.reference(
        from: inertial,
        robotID: descriptor.descriptor.robot.robotID
    )
}

private func loadDescriptor(modelPath: String) throws -> RobotDescriptor? {
    let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let loader = RobotDescriptorLoader()
    let descriptor = try loader.loadDescriptor(path: trimmed)
    return descriptor.descriptor
}

private func loadLoadedDescriptor(modelPath: String) throws -> LoadedRobotDescriptor? {
    let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let loader = RobotDescriptorLoader()
    return try loader.loadDescriptor(path: trimmed)
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
    episodes: Int
) throws -> [ReferenceQuadrotorScenarioDefinition] {
    if let suite {
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
            throw ValidationError("--suite must be one of 6, 7, or 8.")
        }
        let benchmark = try LongHorizonBenchmarkSuite.makeDefault(
            scenariosPerTrack: max(episodes, 1),
            baseSeed: 60_000
        )
        return benchmark.cases
            .filter { $0.track == track }
            .map(\.definition)
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

private func makeRegressionRolloutDefinitions(
    task: RolloutTaskChoice,
    suite: Int,
    episodes: Int
) throws -> [ReferenceQuadrotorScenarioDefinition] {
    guard episodes > 0 else {
        throw ValidationError("--episodes must be greater than 0.")
    }
    return try makeRolloutDefinitions(task: task, suite: suite, episodes: episodes)
}

private func makeLiftSuiteDefinitions(
    task: RolloutTaskChoice,
    suite: Int,
    episodes: Int
) throws -> [ReferenceQuadrotorScenarioDefinition] {
    let baseDefinitions = try baseLiftDefinitions(task: task)
    return try Array(baseDefinitions.prefix(max(1, episodes))).enumerated().map { index, definition in
        try liftRegressionDefinition(
            task: task,
            suite: suite,
            index: index,
            definition: definition
        )
    }
}

private func baseLiftDefinitions(task: RolloutTaskChoice) throws -> [ReferenceQuadrotorScenarioDefinition] {
    switch task {
    case .attitude:
        return try KuyAtt1Suite().scenarios()
    case .lift:
        return try KuyLiftSuite().scenarios()
    case .singleLift:
        return try KuySingleLiftSuite().scenarios()
    }
}

private func liftRegressionDefinition(
    task: RolloutTaskChoice,
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
        throw ValidationError("--suites only supports 6, 7, and 8.")
    }

    let targetZ = max(0.05, liftEnvelope.targetZ + targetOffset)
    let adjustedLiftEnvelope = LiftEnvelope(
        targetZ: targetZ,
        tolerance: liftEnvelope.tolerance,
        maxVelocity: liftEnvelope.maxVelocity,
        warmupTime: liftEnvelope.warmupTime,
        requiredHoldTime: liftEnvelope.requiredHoldTime
    )
    let prefix: String
    switch task {
    case .attitude:
        prefix = "KUY-ATT-M2-S\(suite)"
    case .lift:
        prefix = "KUY-LIFT-M2-S\(suite)"
    case .singleLift:
        prefix = "KUY-SLIFT-M2-S\(suite)"
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
    case .baseline:
        return .baseline
    case .teacherBaseline:
        return .teacherBaseline
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
    loadedDescriptor: LoadedRobotDescriptor? = nil
) throws -> ReferenceQuadrotorParameters {
    if let loadedDescriptor {
        let loader = RobotDescriptorLoader()
        let inertial = try loader.loadPlantInertialProperties(descriptor: loadedDescriptor)
        return try ReferenceQuadrotorParameters.reference(
            from: inertial,
            robotID: loadedDescriptor.descriptor.robot.robotID
        )
    }

    guard task == .singleLift else { return .baseline }
    let baseline = ReferenceQuadrotorParameters.baseline
    return try ReferenceQuadrotorParameters(
        mass: baseline.mass,
        inertia: baseline.inertia,
        armLength: baseline.armLength,
        motorTimeConstant: baseline.motorTimeConstant,
        maxThrust: 12.0,
        yawCoefficient: baseline.yawCoefficient,
        gravity: baseline.gravity,
        aerodynamics: baseline.aerodynamics
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

private func parseDescendingVector(_ raw: String, optionName: String = "--descending") throws -> [Double]? {
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

private func parseDescendingProgram(_ raw: String) throws -> DescendingIntentProgram? {
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
