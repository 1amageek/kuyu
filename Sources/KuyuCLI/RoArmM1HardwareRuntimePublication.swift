import ArgumentParser
import Foundation
import KuyuMLXRoArmM1

struct PublishRoArmM1HardwareRuntime: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish-roarm-m1-hardware-runtime",
        abstract: "Publish measured RoArm M1 runtime evidence into a Manas bundle."
    )

    @Option(help: "Measured RoArm M1 hardware runtime log JSON path under the Manas bundle root.")
    var log: String

    @Option(help: "Manas .manasbundle directory to update.")
    var checkpoint: String

    @Option(
        name: .customLong("report-output"),
        help: "Output hardware runtime report JSON path under the Manas bundle root. Defaults to <checkpoint>/hardware-runtime/roarm-m1-hardware-runtime-report.json."
    )
    var reportOutput: String?

    func run() throws {
        let checkpointURL = URL(fileURLWithPath: checkpoint, isDirectory: true)
        let logURL = bundleScopedURL(log, checkpointURL: checkpointURL, isDirectory: false)
        let reportURL = reportOutput.map {
            bundleScopedURL($0, checkpointURL: checkpointURL, isDirectory: false)
        } ?? checkpointURL
            .appendingPathComponent("hardware-runtime", isDirectory: true)
            .appendingPathComponent("roarm-m1-hardware-runtime-report.json", isDirectory: false)

        let publication = try RoArmM1HardwareRuntimeBundleEvidenceService().publish(
            logURL: logURL,
            checkpointURL: checkpointURL,
            reportURL: reportURL,
        )
        let readiness = try RoArmM1ArmGripperBundleReadinessValidator().validatedBundle(
            in: checkpointURL,
            requirement: .hardwareRuntime
        )
        let report = publication.runtimePublication.report
        let runtimePublication = publication.runtimePublication

        print("[roarm-m1-hardware-runtime] report=\(reportURL.path)")
        print("[roarm-m1-hardware-runtime] artifact=\(runtimePublication.artifactURL.path)")
        print("[roarm-m1-hardware-runtime] bundleEvidence=\(publication.evidenceURL.path)")
        print("[roarm-m1-hardware-runtime] bundle=\(readiness.trainingArtifact.bundleID)")
        print("[roarm-m1-hardware-runtime] run=\(report.runID)")
        if let telemetrySessionID = readiness.hardwareRuntimeBundleEvidence?.telemetrySessionID {
            print("[roarm-m1-hardware-runtime] telemetrySession=\(telemetrySessionID)")
        }
        print("[roarm-m1-hardware-runtime] readiness=\(readiness.readinessLevel.rawValue) source=\(readiness.sourceKind.rawValue)")
        print("[roarm-m1-hardware-runtime] samples=\(report.sampleCount) duration=\(format(report.observedDurationSeconds))")
        print("[roarm-m1-hardware-runtime] feedback=\(report.validatedFeedbackChannelCount)/\(report.feedbackChannelCount) boundedRecovery=\(report.boundedRecovery)")
    }

    private func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private func bundleScopedURL(
        _ path: String,
        checkpointURL: URL,
        isDirectory: Bool
    ) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(fileURLWithPath: trimmed, isDirectory: isDirectory)
        guard !url.path.hasPrefix("/") else {
            return url
        }
        return checkpointURL.appendingPathComponent(trimmed, isDirectory: isDirectory)
    }
}
