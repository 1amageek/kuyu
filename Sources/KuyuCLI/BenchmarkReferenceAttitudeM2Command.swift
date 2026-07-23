import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

struct BenchmarkReferenceAttitudeM2: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark-reference-attitude-m2",
        abstract: "Benchmark a temporal-CTBR reference-attitude checkpoint on M2 suites 6...8."
    )

    @Option(help: "Temporal-CTBR checkpoint bundle directory.")
    var snapshot: String

    @Option(help: "Training arm label recorded in benchmark artifacts.")
    var label: String

    @Option(name: .customLong("artifact-root"), help: "Empty directory where benchmark artifacts are written.")
    var artifactRootPath: String

    @Option(help: "Comma-separated M2 suite list: 6,7,8.")
    var suites: String = "6,7,8"

    @Option(help: "Episodes per M2 suite.")
    var episodes: Int = 3

    @Option(name: .customLong("max-steps"), help: "Maximum steps per episode. Omit for full scenario duration.")
    var maxSteps: Int?

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier0

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(help: "kp gain for evaluator.")
    var kp: Double = 2.0

    @Option(help: "kd gain for evaluator.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for evaluator.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Flag(name: .customLong("quality-gate"), help: "Enable quality gating during benchmark rollout.")
    var qualityGate: Bool = false

    @Flag(name: .customLong("require-all-pass"), help: "Exit non-zero unless every M2 episode passes without violation.")
    var requireAllPass: Bool = false

    mutating func run() async throws {
        let trimmedSnapshot = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSnapshot.isEmpty else {
            throw ValidationError("--snapshot must not be empty.")
        }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else {
            throw ValidationError("--label must not be empty.")
        }
        let trimmedArtifactRoot = artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArtifactRoot.isEmpty else {
            throw ValidationError("--artifact-root must not be empty.")
        }
        guard episodes > 0 else {
            throw ValidationError("--episodes must be greater than 0.")
        }
        if let maxSteps, maxSteps <= 0 {
            throw ValidationError("--max-steps must be greater than 0 when specified.")
        }

        let selectedSuites = try parseM2BenchmarkSuites(suites)
        let checkpointURL = URL(fileURLWithPath: trimmedSnapshot, isDirectory: true)
        let artifactRoot = URL(fileURLWithPath: trimmedArtifactRoot, isDirectory: true)
        let evaluatorConfig = ManasMLXReferenceQuadrotorCheckpointEvaluatorConfig(
            robotManifestPath: model,
            determinism: try makeDeterminism(tier: tier),
            schedule: try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps),
            gains: try ImuRateDampingCutGains(
                kp: kp,
                kd: kd,
                yawDamping: yawDamping,
                hoverThrustScale: hoverScale
            ),
            useQualityGating: qualityGate
        )
        let result = try await ReferenceQuadrotorM2BenchmarkService().run(
            ReferenceQuadrotorM2BenchmarkRequest(
                label: trimmedLabel,
                checkpointURL: checkpointURL,
                artifactRoot: artifactRoot,
                suites: selectedSuites,
                episodesPerSuite: episodes,
                maxStepsPerEpisode: maxSteps,
                evaluatorConfig: evaluatorConfig
            ),
            onEvent: Self.printM2BenchmarkEvent
        )
        let allPassed = result.decision.allPassed
        print("[attitude-m2-benchmark] label=\(trimmedLabel) allPassed=\(allPassed) artifact=\(result.artifactURL.path)")
        print("[attitude-m2-benchmark] legacySuiteQuality=\(result.legacySuiteQualityURL.path)")
        if requireAllPass && !allPassed {
            throw ExitCode.failure
        }
    }

    private func parseM2BenchmarkSuites(_ raw: String) throws -> [Int] {
        let values = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else {
            throw ValidationError("--suites must include at least one M2 suite.")
        }
        var seenSuites = Set<Int>()
        var suites: [Int] = []
        for value in values {
            guard let suite = Int(value), (6...8).contains(suite) else {
                throw ValidationError("--suites supports M2 attitude suites 6,7,8.")
            }
            guard seenSuites.insert(suite).inserted else {
                throw ValidationError("--suites contains a duplicate suite: \(suite)")
            }
            suites.append(suite)
        }
        return suites
    }

    private static func printM2BenchmarkEvent(_ event: ReferenceQuadrotorM2BenchmarkEvent) {
        switch event {
        case .suiteStarted(let label, let suite, let episodes):
            print("RR-M2-BENCH label=\(label) suite=\(suite) episodes=\(episodes) state=start")
        case .suiteCompleted(
            let label,
            let suite,
            let track,
            let taskPassCount,
            let episodeCount,
            let violationRate,
            let averageSurvivalTime,
            let minimumSurvivalTime,
            let averageReward
        ):
            let summary = [
                "RR-M2-BENCH label=\(label) suite=\(suite) track=\(track)",
                "episodes=\(episodeCount) pass=\(taskPassCount)",
                "violationRate=\(String(format: "%.3f", violationRate))",
                "survivalAvg=\(String(format: "%.2f", averageSurvivalTime))",
                "survivalMin=\(String(format: "%.2f", minimumSurvivalTime))",
                "rewardAvg=\(String(format: "%.3f", averageReward))"
            ].joined(separator: " ")
            print(summary)
        case .artifactWritten(let path):
            print("[attitude-m2-benchmark] artifact-written path=\(path)")
        case .legacySuiteQualityWritten(let path):
            print("[attitude-m2-benchmark] legacy-suite-quality-written path=\(path)")
        }
    }
}
