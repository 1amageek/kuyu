import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuPhysics
import KuyuTraining

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
        try createFreshBiasCalibrationArtifactRoot(artifactRoot)

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
        let checkpointEvaluatorConfig = ManasMLXReferenceQuadrotorCheckpointEvaluatorConfig(
            robotManifestPath: model,
            determinism: determinism,
            schedule: schedule,
            gains: gains,
            useQualityGating: !noQualityGate
        )
        let checkpointEvaluationService = ReferenceQuadrotorCheckpointEvaluationService()
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
                _ = try await checkpointEvaluationService.evaluate(
                    ReferenceQuadrotorCheckpointEvaluationRunRequest(
                        profile: profile,
                        checkpointURL: candidateCheckpointURL,
                        artifactRoot: evaluationRoot,
                        evaluatorConfig: checkpointEvaluatorConfig,
                        requiresPolicyPass: true
                    )
                )
                checkpointEvaluationPassed = true
                checkpointEvaluationReasons = []
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

private func createFreshBiasCalibrationArtifactRoot(_ artifactRoot: URL) throws {
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
            throw ValidationError("--suites supports 0-8 (attitude 0-5 = A1 conformance suites, 6-8 = long-horizon tracks).")
        }
        guard seenSuites.insert(suite).inserted else {
            throw ValidationError("--suites contains a duplicate suite: \(suite)")
        }
        return suite
    }
}
