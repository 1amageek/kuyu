import ArgumentParser
import Foundation
import KuyuMLXRoArmM1
import KuyuPhysics

struct PublishRoArmM1HardwareCalibration: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish-roarm-m1-hardware-calibration",
        abstract: "Build a validated RoArm M1 hardware calibration report from measured observations."
    )

    @Option(help: "RoARM M1 robot manifest path.")
    var model: String = "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json"

    @Option(help: "Hardware calibration plan JSON path.")
    var plan: String

    @Option(help: "Measured calibration observation JSON array path.")
    var observations: String

    @Option(help: "Output hardware calibration report JSON path.")
    var output: String

    @Option(help: "Report identifier to persist in the generated calibration report.")
    var reportID: String

    @Option(name: .customLong("measurement-system"), help: "Measured calibration system identifier.")
    var measurementSystem: String

    @Option(name: .customLong("measurement-device-id"), help: "Measured calibration device identifier.")
    var measurementDeviceID: String

    @Option(name: .customLong("operator-id"), help: "Optional operator identifier.")
    var operatorID: String?

    @Option(name: .customLong("firmware-version"), help: "Optional RoArm M1 firmware version.")
    var firmwareVersion: String?

    @Option(name: .customLong("notes"), help: "Optional calibration notes.")
    var notes: String?

    @Option(name: .customLong("generated-at"), help: "ISO8601 report timestamp. Defaults to the current time.")
    var generatedAt: String?

    @Option(name: .customLong("position-tolerance"), help: "Hardware parity position tolerance in radians.")
    var positionToleranceRadians: Double = 0.05

    @Option(name: .customLong("minimum-samples-per-joint"), help: "Minimum samples required per active joint.")
    var minimumSamplesPerJoint: Int = 3

    func run() throws {
        let loaded = try KuyuModelLoader().loadRobot(path: model)
        let publication = try RoArmM1HardwareCalibrationReportService().writeReport(
            for: RoArmM1HardwareCalibrationReportPublicationRequest(
                reportID: reportID,
                generatedAt: generatedAtValue,
                robot: loaded,
                planURL: URL(fileURLWithPath: plan, isDirectory: false),
                observationsURL: URL(fileURLWithPath: observations, isDirectory: false),
                reportURL: URL(fileURLWithPath: output, isDirectory: false),
                source: HardwareCalibrationSource(
                    operatorID: operatorID,
                    deviceID: measurementDeviceID,
                    firmwareVersion: firmwareVersion,
                    measurementSystem: measurementSystem,
                    notes: notes
                ),
                positionToleranceRadians: positionToleranceRadians,
                minimumSamplesPerJoint: minimumSamplesPerJoint
            )
        )

        print("[roarm-m1-hardware-calibration] report=\(publication.reportURL.path)")
        print("[roarm-m1-hardware-calibration] reportID=\(publication.report.reportID)")
        print("[roarm-m1-hardware-calibration] robot=\(publication.report.robotID)")
        print("[roarm-m1-hardware-calibration] measurementSystem=\(publication.evidence.measurementSystem)")
        print("[roarm-m1-hardware-calibration] measurementDeviceID=\(publication.evidence.measurementDeviceID)")
        print("[roarm-m1-hardware-calibration] readiness=\(publication.evidence.readinessLevel.rawValue)")
        print("[roarm-m1-hardware-calibration] joints=\(publication.evidence.measuredJointCount)")
        print("[roarm-m1-hardware-calibration] maxObservedErrorRadians=\(format(publication.evidence.maximumObservedErrorRadians))")
    }

    private var generatedAtValue: String {
        if let generatedAt, !generatedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return generatedAt
        }
        return ISO8601DateFormatter().string(from: Date())
    }

    private func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
