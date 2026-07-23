import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuPhysics
import KuyuScenarios
import KuyuTraining
import ManasCore

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
        let backend = await ManasMLXTrainingBackend(
            runtime: ManasMLXTrainingRuntime(modelStore: workerStore),
            saveDirectory: checkpointDirectory,
            rolloutDatasetLoader: ReferenceQuadrotorTemporalRolloutDatasetLoaderFactory.make()
        )
        let orchestrator = TrainingRunOrchestrator(
            scenarioExecutor: CLIScenarioExecutor(
                store: scenarioStore,
                parameters: parameters,
                schedule: schedule,
                embodiment: embodiment
            ),
            backend: backend,
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

}
