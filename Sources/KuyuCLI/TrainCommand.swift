import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLX
import KuyuMLXCore
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

/// Contract-managed training entry point.
///
/// Unlike `loop`, every run executes under the durable training-run contract:
/// one directory per run containing the write-once manifest, the append-only
/// iteration journal, heartbeats, the control channel (pause/resume/stop at
/// iteration boundaries), and the terminal outcome. Artifacts (datasets,
/// checkpoints, convergence reports) live inside the run directory.
struct Train: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "train",
        abstract: "Run a ManasMLX training run under the training-run contract (journal, heartbeat, pause/resume/stop)."
    )

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

    @Option(name: .customLong("run-root"), help: "Run root directory. Defaults to KUYU_RUN_ROOT or ~/.kuyu/runs.")
    var runRootPath: String?

    @Option(name: .customLong("task-label"), help: "Task label recorded in the run manifest and run ID.")
    var taskLabel: String = "attitude-supervised"

    @Option(help: "Capability profile recorded in the run manifest.")
    var profile: String = "P1"

    @Option(help: "Repository directory anchoring the recorded code identity. Defaults to the current directory.")
    var repository: String?

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
        if let maxBatches, maxBatches <= 0 {
            throw ValidationError("--max-batches must be positive when specified.")
        }

        let runRoot = try resolveTrainingRunRoot(override: runRootPath)
        let repositoryDirectory = URL(
            fileURLWithPath: repository ?? FileManager.default.currentDirectoryPath,
            isDirectory: true
        )

        // Seed the global MLX RNG before any model is constructed so the
        // manifest's determinism stamp matches the actual run.
        let mlxGlobalSeed = try TrainingRunDriver.resolveMLXGlobalSeed(
            environment: ProcessInfo.processInfo.environment
        )
        ManasMLXRandomSeed.seed(mlxGlobalSeed)

        let determinismTier: Int
        switch tier {
        case .tier0: determinismTier = 0
        case .tier1: determinismTier = 1
        case .tier2: determinismTier = 2
        }

        let driver = try TrainingRunDriver.begin(
            task: taskLabel,
            profile: profile,
            semanticVersion: "kuyu-train-v1",
            cacheKey: "kuyu-train-v1",
            mlxGlobalSeed: mlxGlobalSeed,
            noiseSeedSalt: nil,
            determinismTier: determinismTier,
            runRoot: runRoot,
            repositoryDirectory: repositoryDirectory
        )
        let runDirectory = URL(fileURLWithPath: driver.runDirectoryPath, isDirectory: true)
        let artifactDirectory = runDirectory.appendingPathComponent("artifacts", isDirectory: true)
        let checkpointDirectory = artifactDirectory.appendingPathComponent("checkpoints", isDirectory: true)
        print("[train] run=\(driver.runIDString)")
        print("[train] directory=\(runDirectory.path)")

        let request = SimulationRunRequest(
            controller: .manasMLX,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            robotManifestPath: model,
            overrideParameters: model.isEmpty ? nil : parameters,
            useAux: !noAux,
            useQualityGating: !noQualityGate
        )

        let scenarioStore = ManasMLXModelStore()
        let workerStore = ManasMLXModelStore()
        try MLXRuntimeReadinessService().check()

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
            datasetURL: artifactDirectory,
            sequenceLength: sequenceLength,
            epochs: epochs,
            learningRate: learningRate,
            useAux: !noAux,
            useQualityGating: !noQualityGate,
            maxBatches: maxBatches
        )

        let collector = TrainingRunEventCollector()
        let result = await orchestrator.run(
            config: config,
            runRequest: request,
            trainingTemplate: trainingTemplate,
            artifactDirectory: artifactDirectory,
            onIterationBoundary: { iteration in
                try Self.journal(collector.drainCompleted(before: iteration), driver: driver)
                try driver.writeHeartbeat(iteration: iteration, phase: "iteration-start")
                switch try await driver.applyPendingControl(iteration: iteration) {
                case .continueRun:
                    return .continueRun
                case .stopRun:
                    return .stopRun
                }
            },
            onEvent: { event in
                collector.ingest(event)
                Self.printEvent(event)
            }
        )

        // Journal observations from the final (or torn) iteration before the
        // outcome is recorded, regardless of how the run ended.
        do {
            try Self.journal(collector.drainAll(), driver: driver)
        } catch {
            print("[train] WARNING: failed to journal final iteration records: \(error)")
        }

        print("[train] terminal=\(result.manifest.terminalState.rawValue) accepted=\(result.convergence.accepted) reason=\(result.convergence.reason)")
        switch result.manifest.terminalState {
        case .completed:
            let acceptedPath: String?
            if let published = result.checkpointDecision.publishedCheckpointURL {
                acceptedPath = published.path
            } else if result.checkpointDecision.state == .accepted {
                acceptedPath = result.checkpointDecision.candidateCheckpointURL?.path
            } else {
                acceptedPath = nil
            }
            try driver.finishCompleted(acceptedCheckpointPath: acceptedPath)
        case .rejected:
            try driver.finishCompleted(acceptedCheckpointPath: nil)
        case .cancelled:
            try driver.finishCancelled(acceptedCheckpointPath: nil)
            print("[train] run cancelled by control command")
        case .failed, .running:
            let reason = result.manifest.failureReason ?? "unknown failure"
            driver.finishFailedReportingSecondaryFailure(reason: reason)
            print("[train] run failed: \(reason)")
            throw ExitCode.failure
        }
    }

    @MainActor
    private static func journal(
        _ completed: [TrainingRunEventCollector.CompletedIteration],
        driver: TrainingRunDriver
    ) throws {
        for item in completed {
            var checkpoint: TrainingRunIterationRecord.CheckpointReference?
            if let url = item.checkpointURL {
                checkpoint = try driver.checkpointReference(for: url)
            }
            let record = TrainingRunIterationRecord(
                iteration: item.orchestratorIteration - 1,
                recordedAt: Date(),
                evaluation: TrainingRunIterationRecord.EvaluationRecord(
                    evaluationHorizon: 0,
                    metrics: item.metrics
                ),
                checkpoint: checkpoint
            )
            try driver.recordIteration(record)
        }
    }

    private static func printEvent(_ event: TrainingRunEvent) {
        switch event {
        case .iterationStarted(let iteration):
            print("[train] iter=\(iteration) started")
        case .suiteCompleted(let iteration, let output, let score):
            let overshoot = output.summary.aggregate.worstOvershootDegrees ?? -1
            let recovery = output.summary.aggregate.averageRecoveryTime ?? -1
            let hf = output.summary.aggregate.averageHfStabilityScore ?? -1
            print("[train] iter=\(iteration) score=\(String(format: "%.3f", score)) overshoot=\(String(format: "%.2f", overshoot)) recovery=\(String(format: "%.2f", recovery)) hf=\(String(format: "%.2f", hf))")
        case .datasetExported(let iteration, let directory, let count):
            print("[train] iter=\(iteration) dataset exported count=\(count) path=\(directory)")
        case .trainingCompleted(let iteration, let backendResult):
            print("[train] iter=\(iteration) training loss=\(String(format: "%.6f", backendResult.finalLoss))")
        case .convergenceUpdated(let summary):
            print("[train] convergence accepted=\(summary.accepted) reason=\(summary.reason)")
        default:
            break
        }
    }
}
