import ArgumentParser
import Foundation
import KuyuTraining

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

    @Flag(name: .customLong("allow-rejected"), help: "Exit zero after writing a rejected probe artifact.")
    var allowRejected: Bool = false

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

        let sourceCheckpointURL = sourceCheckpointURL(from: sourceCheckpointPath)
        if workers > 1, sourceCheckpointURL == nil {
            throw ValidationError("--workers greater than 1 requires --source-checkpoint so every worker can lease an isolated snapshot.")
        }
        let artifactRoot: URL
        if let artifactRootPath, !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        } else {
            artifactRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-probe-\(UUID().uuidString)", isDirectory: true)
        }

        let result = try await runCLIManasProbe(
            task: task,
            tier: tier,
            cutPeriodSteps: cutPeriodSteps,
            model: model,
            sourceCheckpointURL: sourceCheckpointURL,
            artifactRoot: artifactRoot,
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
            mlxSeed: mlxSeed,
            printEvents: true
        )

        print("[probe] artifacts path=\(artifactRoot.path)")
        print("[probe] terminal=\(result.manifest.terminalState.rawValue)")
        print("[probe] teacherScore=\(String(format: "%.3f", result.comparison.teacherScore)) initialScore=\(String(format: "%.3f", result.comparison.initialScore))")
        if let trainedScore = result.comparison.trainedScore, let scoreDelta = result.comparison.scoreDelta {
            print("[probe] trainedScore=\(String(format: "%.3f", trainedScore)) delta=\(String(format: "%.3f", scoreDelta))")
        } else {
            print("[probe] trainedScore=n/a delta=n/a")
        }
        let artifactReader = KuyuCLITrainingArtifactReader()
        let validated = try artifactReader.validatedProbeArtifacts(in: artifactRoot)
        print("[probe] artifactValid=true trainingRun=\(validated.training.manifest.runID) metrics=\(validated.training.metrics.count)")
        print("[probe] trainingCheckpoint=\(validated.comparison.checkpointDecision.rawValue) probeCheckpoint=\(validated.probeCheckpointDecision.state.rawValue) reload=\(validated.comparison.reloadSucceeded)")
        print("[probe] selectedCheckpoint role=\(validated.comparison.selectedCheckpointRole.rawValue) path=\(validated.comparison.selectedCheckpointURL?.path ?? "n/a")")
        print("[probe] probeAccepted=\(validated.comparison.probeAccepted) reasons=\(validated.comparison.probeRejectionReasons.joined(separator: ","))")
        switch validated.manifest.terminalState {
        case .completed:
            let acceptance = try artifactReader.validatedManasMLXProbeAcceptance(in: artifactRoot)
            print("[probe] acceptanceValid=true datasets=\(acceptance.probe.datasetCount) publishedCheckpoint=\(acceptance.probe.publishedCheckpointURL.path) coreDigest=\(acceptance.publishedCoreWeightsDigest)")
        case .rejected where allowRejected:
            return
        case .rejected:
            throw ValidationError(
                "probe rejected: \(validated.comparison.probeRejectionReasons.joined(separator: ","))"
            )
        case .failed, .cancelled, .running:
            throw ValidationError(
                "probe did not complete: terminal=\(validated.manifest.terminalState.rawValue) reason=\(validated.manifest.failureReason ?? "unspecified")"
            )
        }
    }
}
