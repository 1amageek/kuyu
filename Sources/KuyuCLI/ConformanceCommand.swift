import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLX
import KuyuPhysics
import KuyuScenarios

/// Runs the A1 conformance suites against the analytical baseline controller
/// and publishes the report required by `A1_MANAS_CONFORMANCE_SUITE.md`:
/// suite + seed list, per-scenario metric summary, aggregate summary, and
/// learning flags. Artifacts are written as `report.json` and `report.md`.
struct Conformance: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "conformance",
        abstract: "Run A1 conformance suites (0–5) with replay verification and publish a JSON + Markdown report."
    )

    @Option(help: "Comma-separated suite levels to run (0–5).")
    var suites: String = "0,1,2,3,4,5"

    @Option(help: "Controller: activeAltitudeHold (privileged teacher) or sensorBaseline (rate damping only). Both are replay-verified.")
    var controller: ControllerChoice = .activeAltitudeHold

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(help: "Comma-separated scenario seeds.")
    var seeds: String = "2001,2002,2003"

    @Option(help: "Scenario duration in seconds.")
    var duration: Double = 20.0

    @Option(help: "kp gain for the baseline controller.")
    var kp: Double = 2.0
    @Option(help: "kd gain for the baseline controller.")
    var kd: Double = 0.25
    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for the baseline controller.")
    var yawDamping: Double = 0.2
    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Option(help: "Directory for the conformance report artifacts.")
    var output: String = "/tmp/kuyu-conformance"

    mutating func run() async throws {
        guard controller != .manasMLX else {
            throw ValidationError("conformance runs baseline controllers only. Use evaluate-manas-checkpoint for trained checkpoints.")
        }
        let levels = try parseLevels(suites)
        let seedValues = try parseSeeds(seeds)
        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: 2)
        let gains = try ImuRateDampingCutGains(kp: kp, kd: kd, yawDamping: yawDamping, hoverThrustScale: hoverScale)
        let parameters = try ReferenceQuadrotorParameterResolutionService().parameters(
            taskMode: .attitude,
            hoverThrustScale: hoverScale
        )

        let outputRoot = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        print("[conformance] controller=\(controller.rawValue) suites=\(levels.map(\.suiteID).joined(separator: ",")) tier=\(tier.rawValue) seeds=\(seedValues.map(String.init).joined(separator: ","))")

        var entries: [A1ConformanceReport.SuiteEntry] = []
        for (index, level) in levels.enumerated() {
            print("[conformance \(index + 1)/\(levels.count)] \(level.suiteID): \(level.title)")
            let suite = A1ConformanceSuite(level: level, seeds: seedValues, duration: duration)
            let summary = try await runSuite(
                suite: suite,
                parameters: parameters,
                schedule: schedule,
                determinism: determinism,
                gains: gains
            )
            entries.append(A1ConformanceReport.SuiteEntry(
                suiteID: level.suiteID,
                level: level.rawValue,
                title: level.title,
                seeds: seedValues,
                summary: summary
            ))
            let replayDetail: String
            switch summary.replay {
            case .performed(let checks):
                replayDetail = "replay=\(checks.filter(\.passed).count)/\(checks.count)"
            case .notPerformed(let reason):
                replayDetail = "replay=not performed (\(reason))"
            }
            print("[conformance]   \(summary.suitePassed ? "PASS" : "FAIL") — scenarios=\(summary.evaluations.count) \(replayDetail)")
        }

        let report = A1ConformanceReportFactory().makeReport(
            controller: controllerDescription,
            determinismTier: determinism.tier,
            learning: A1ConformanceReport.LearningFlags(core: false, reflex: false),
            suites: entries,
            generatedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonURL = outputRoot.appendingPathComponent("report.json")
        try (try encoder.encode(report)).write(to: jsonURL, options: [.atomic])

        let markdownURL = outputRoot.appendingPathComponent("report.md")
        try Data(renderMarkdown(report: report).utf8).write(to: markdownURL, options: [.atomic])

        print("")
        print("[conformance] report.json: \(jsonURL.path)")
        print("[conformance] report.md:   \(markdownURL.path)")
        if report.passed {
            print("[conformance] ALL SUITES PASSED")
        } else {
            print("[conformance] FAILED")
            throw ExitCode.failure
        }
    }

    private var controllerDescription: String {
        switch controller {
        case .activeAltitudeHold:
            return "teacher baseline (privileged altitude hold)"
        case .sensorBaseline:
            return "sensor baseline (ImuRateDampingDriveCut + FixedQuadMotorNerve)"
        case .manasMLX:
            return "manas MLX checkpoint"
        }
    }

    private func runSuite(
        suite: A1ConformanceSuite,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        determinism: DeterminismConfig,
        gains: ImuRateDampingCutGains
    ) async throws -> ValidationSummary {
        switch controller {
        case .activeAltitudeHold:
            // The privileged teacher runs through the RL environment; the runner
            // re-runs every scenario with a fresh environment + policy and
            // compares the logs via ReplayChecker (replayVerification: true).
            let runner = KuyAtt1Runner(
                parameters: parameters,
                schedule: schedule,
                determinism: determinism,
                noise: .zero,
                environment: .standard,
                gains: gains,
                baselineMode: .teacher,
                replayVerification: true
            )
            let definitions = try suite.scenarios()
            let output = try await runner.runWithLogs(definitions: definitions)
            return output.summary
        case .sensorBaseline, .manasMLX:
            // manasMLX is rejected in run(); only the sensor baseline reaches
            // this path. It executes the full replay verification harness.
            let runner = ReferenceQuadrotorScenarioRunner<ImuRateDampingDriveCut, FixedQuadMotorNerve>(
                parameters: parameters,
                schedule: schedule,
                determinism: determinism,
                noise: .zero,
                environment: .standard,
                hoverThrustScale: gains.hoverThrustScale
            )
            let mixer = runner.mixer
            let validation = KuyAtt1Validation(runner: runner, suite: suite)
            let output = try await validation.runWithLogs(
                cutFactory: { _ in
                    try ImuRateDampingDriveCut(
                        hoverThrust: parameters.mass * parameters.gravity / 4.0 * gains.hoverThrustScale,
                        kp: gains.kp,
                        kd: gains.kd,
                        yawDamping: gains.yawDamping,
                        armLength: parameters.armLength,
                        yawCoefficient: parameters.yawCoefficient,
                        maxThrust: parameters.maxThrust,
                        initialRoll: 0,
                        initialPitch: 0,
                        tiltCorrectionTimeConstant: 0.4
                    )
                },
                motorNerveFactory: { _ in
                    FixedQuadMotorNerve(config: FixedQuadMotorNerve.Config(
                        mixer: mixer,
                        motorMaxThrusts: try MotorMaxThrusts.uniform(parameters.maxThrust)
                    ))
                }
            )
            return KuyAtt1RunOutputFactory().makeOutput(
                result: output.result,
                logs: output.logs,
                manifest: output.manifest
            ).summary
        }
    }

    private func parseLevels(_ raw: String) throws -> [A1ConformanceSuite.Level] {
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else {
            throw ValidationError("--suites must list at least one level (0–5).")
        }
        return try parts.map { part in
            guard let value = Int(part), let level = A1ConformanceSuite.Level(rawValue: value) else {
                throw ValidationError("Invalid suite level '\(part)'. Expected integers 0–5.")
            }
            return level
        }
    }

    private func parseSeeds(_ raw: String) throws -> [UInt64] {
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else {
            throw ValidationError("--seeds must list at least one seed.")
        }
        return try parts.map { part in
            guard let value = UInt64(part) else {
                throw ValidationError("Invalid seed '\(part)'. Expected unsigned integers.")
            }
            return value
        }
    }

    private func renderMarkdown(report: A1ConformanceReport) -> String {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("# A1 Conformance Report")
        lines.append("")
        lines.append("- Controller: \(report.controller)")
        lines.append("- Determinism tier: \(report.determinismTier.rawValue)")
        lines.append("- Learning flags: core=\(report.learning.core) reflex=\(report.learning.reflex)")
        lines.append("- Generated: \(formatter.string(from: report.generatedAt))")
        lines.append("- Overall: \(report.passed ? "PASS" : "FAIL")")
        lines.append("")
        lines.append("## Suite Summary")
        lines.append("")
        lines.append("| Suite | Title | Seeds | Scenarios | Passed | Avg Recovery (s) | Worst Overshoot (deg) | Avg HF Score | Replay |")
        lines.append("|---|---|---|---|---|---|---|---|---|")
        for entry in report.suites {
            let aggregate = entry.summary.aggregate
            let replayCell: String
            switch entry.summary.replay {
            case .performed(let checks):
                replayCell = "\(checks.filter(\.passed).count)/\(checks.count) passed"
            case .notPerformed:
                replayCell = "not performed"
            }
            lines.append("| \(entry.suiteID) | \(entry.title) | \(entry.seeds.map(String.init).joined(separator: ", ")) | \(entry.summary.evaluations.count) | \(entry.summary.suitePassed ? "PASS" : "FAIL") | \(format(aggregate.averageRecoveryTime)) | \(format(aggregate.worstOvershootDegrees)) | \(format(aggregate.averageHfStabilityScore)) | \(replayCell) |")
        }
        for entry in report.suites {
            lines.append("")
            lines.append("## \(entry.suiteID): \(entry.title)")
            lines.append("")
            lines.append("| Scenario | Seed | Passed | Max ω (rad/s) | Max Tilt (deg) | Recovery (s) | Overshoot (deg) | HF Score | Failures |")
            lines.append("|---|---|---|---|---|---|---|---|---|")
            for evaluation in entry.summary.evaluations {
                let failures = evaluation.failures.isEmpty ? "—" : evaluation.failures.joined(separator: "; ")
                lines.append("| \(evaluation.scenarioId.rawValue) | \(evaluation.seed.rawValue) | \(evaluation.passed ? "PASS" : "FAIL") | \(format(evaluation.maxOmega)) | \(format(evaluation.maxTiltDegrees)) | \(format(evaluation.recoveryTimeSeconds)) | \(format(evaluation.overshootDegrees)) | \(format(evaluation.hfStabilityScore)) | \(failures) |")
            }
            if let reason = entry.summary.replay.notPerformedReason {
                lines.append("")
                lines.append("Replay verification not performed: \(reason)")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.3f", value)
    }
}
