import ArgumentParser
import Darwin
import Foundation
import KuyuCore
import KuyuMLX
import KuyuPhysics

struct ProbeRoArmM1: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe-roarm-m1",
        abstract: "Generate or send a guarded RoARM M1 hardware probe command."
    )

    @Option(help: "RoARM M1 robot manifest path.")
    var model: String = "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json"

    @Option(help: "Comma-separated arm and gripper targets in radians, exactly five values.")
    var joints: String = "0,0,0,0,0"

    @Option(help: "Waveshare JSON speed field S1...S5.")
    var speed: Int = 0

    @Option(help: "Waveshare JSON acceleration field A1...A5.")
    var acceleration: Int = 60

    @Option(help: "Serial device path. Motion is never sent unless --enable-motion is present.")
    var device: String = ""

    @Flag(name: .customLong("enable-motion"), help: "Actually write the command to --device.")
    var enableMotion: Bool = false

    @Flag(name: .customLong("use-model-limits"), help: "Use full model joint ranges instead of the safe commissioning clamp.")
    var useModelLimits: Bool = false

    @Option(name: .customLong("write-calibration-plan"), help: "Write a guarded hardware parity calibration plan JSON and exit.")
    var calibrationPlanOutput: String?

    @Option(name: .customLong("calibration-amplitude"), help: "Calibration sweep amplitude in radians.")
    var calibrationAmplitude: Double = 0.174533

    @Option(name: .customLong("calibration-hold"), help: "Hold time per calibration step in seconds.")
    var calibrationHoldSeconds: Double = 1.0

    @Option(name: .customLong("calibration-repetitions"), help: "Calibration sweep repetitions per joint.")
    var calibrationRepetitions: Int = 2

    @Option(name: .customLong("validate-calibration-report"), help: "Validate a hardware calibration report JSON against the RoArm M1 model.")
    var calibrationReportPath: String?

    func run() throws {
        let loaded = try KuyuModelLoader().loadRobot(path: model)
        let embodiment = loaded.embodiment
        try validateRoArmM1Manifest(loaded)

        let jointTargets = try parseJointTargets(joints)
        let modelJointLimits = try jointLimits(from: embodiment.signals.drive)
        let encoderJointLimits: [ClosedRange<Double>]
        if useModelLimits {
            encoderJointLimits = modelJointLimits
        } else {
            encoderJointLimits = try safeCommissioningLimits(within: modelJointLimits)
        }

        if let calibrationReportPath {
            try validateCalibrationReport(path: calibrationReportPath, loaded: loaded)
        }

        if let calibrationPlanOutput {
            let plan = try RoArmM1HardwareCalibrationPlanBuilder().build(
                robot: loaded,
                jointLimits: encoderJointLimits,
                speed: speed,
                acceleration: acceleration,
                amplitudeRadians: calibrationAmplitude,
                holdSeconds: calibrationHoldSeconds,
                repetitions: calibrationRepetitions
            )
            try writeJSON(plan, to: calibrationPlanOutput)
            print("[roarm-m1] calibrationPlan=\(calibrationPlanOutput)")
            print("[roarm-m1] calibrationSteps=\(plan.steps.count)")
            print("[roarm-m1] calibrationMotion=not-executed; send individual reviewed steps with --enable-motion")
            return
        }

        try validateTargets(jointTargets, against: encoderJointLimits, field: "--joints")

        var motorNerve = try MotorNerveChain(contract: embodiment)
        let drives = try jointTargets.enumerated().map { index, value in
            try DriveIntent(index: DriveIndex(UInt32(index)), activation: value)
        }
        let actuators = try motorNerve.update(
            input: drives,
            corrections: [],
            telemetry: MotorNerveTelemetry(actuatorTelemetry: ActuatorTelemetrySnapshot(channels: [])),
            time: try WorldTime(stepIndex: 0, time: 0.0)
        )

        let encoder = try RoArmM1ServoCommandEncoder(
            jointLimits: encoderJointLimits,
            speed: speed,
            acceleration: acceleration
        )
        let command = try encoder.command(forActuatorValues: actuators)
        let data = try encoder.commandData(forActuatorValues: actuators)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw ValidationError("Generated command payload is not UTF-8.")
        }

        print("[roarm-m1] robot=\(loaded.manifest.robotID)")
        print("[roarm-m1] joints=\(format(jointTargets))")
        print("[roarm-m1] actuatorValues=\(format(actuators.map { $0.value }))")
        print("[roarm-m1] pulses=\(command.positions)")
        print("[roarm-m1] payload=\(payload)")

        guard enableMotion else {
            print("[roarm-m1] motion=disabled; pass --enable-motion --device <path> to write serial bytes")
            return
        }

        let trimmedDevice = device.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDevice.isEmpty else {
            throw ValidationError("--device is required when --enable-motion is present.")
        }
        try RoArmM1SerialWriter.write(data: data, to: trimmedDevice)
        print("[roarm-m1] motion=sent device=\(trimmedDevice) bytes=\(data.count)")
    }

    private func validateRoArmM1Manifest(_ loaded: LoadedKuyuRobot) throws {
        let embodiment = loaded.embodiment
        let body = loaded.body
        guard loaded.manifest.robotID == "roarm-m1-v0" else {
            throw ValidationError("Expected roarm-m1-v0 robot, got \(loaded.manifest.robotID).")
        }
        guard embodiment.control.driveChannels.count == RoArmM1ServoCommandEncoder.jointCount else {
            throw ValidationError("RoARM M1 embodiment must define exactly five drive channels.")
        }
        guard embodiment.signals.actuator.count == RoArmM1ServoCommandEncoder.jointCount else {
            throw ValidationError("RoARM M1 embodiment must define exactly five actuator channels.")
        }
        let attachments = body.actuatorAttachments.sorted { $0.actuatorID < $1.actuatorID }
        guard attachments.count == RoArmM1ServoCommandEncoder.jointCount else {
            throw ValidationError("RoARM M1 body must define exactly five actuator attachments.")
        }
        for (index, attachment) in attachments.enumerated() {
            let expectedDirection = RoArmM1ServoCommandEncoder.commandDirections[index]
            let expectedReduction = RoArmM1ServoCommandEncoder.mechanicalReductionRatios[index]
            guard attachment.commandDirection == expectedDirection else {
                throw ValidationError(
                    "RoARM M1 body command direction for \(attachment.actuatorID) is \(attachment.commandDirection), expected \(expectedDirection)."
                )
            }
            guard attachment.mechanicalReductionRatio == expectedReduction else {
                throw ValidationError(
                    "RoARM M1 body reduction for \(attachment.actuatorID) is \(attachment.mechanicalReductionRatio), expected \(expectedReduction)."
                )
            }
            guard attachment.transmissionRatio == expectedReduction else {
                throw ValidationError(
                    "RoARM M1 body transmission ratio for \(attachment.actuatorID) is \(attachment.transmissionRatio), expected \(expectedReduction)."
                )
            }
            guard attachment.mountFrameID != nil else {
                throw ValidationError("RoARM M1 actuator attachment \(attachment.actuatorID) is missing mountFrameID.")
            }
        }
    }

    private func parseJointTargets(_ raw: String) throws -> [Double] {
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == RoArmM1ServoCommandEncoder.jointCount else {
            throw ValidationError("--joints must contain exactly five comma-separated finite numbers.")
        }

        var values: [Double] = []
        values.reserveCapacity(parts.count)
        for part in parts {
            guard !part.isEmpty, let value = Double(part), value.isFinite else {
                throw ValidationError("Invalid --joints value '\(part)'.")
            }
            values.append(value)
        }
        return values
    }

    private func validateTargets(_ targets: [Double], against limits: [ClosedRange<Double>], field: String) throws {
        guard limits.count == targets.count else {
            throw ValidationError("\(field) count does not match the RoARM M1 joint limit count.")
        }
        for (index, target) in targets.enumerated() {
            let limit = limits[index]
            guard limit.contains(target) else {
                throw ValidationError(
                    "\(field)[\(index)] \(target) exceeds active probe range [\(limit.lowerBound), \(limit.upperBound)]."
                )
            }
        }
    }

    private func jointLimits(from signals: [SignalDefinition]) throws -> [ClosedRange<Double>] {
        let sortedSignals = signals.sorted { $0.index < $1.index }
        guard sortedSignals.count == RoArmM1ServoCommandEncoder.jointCount else {
            throw ValidationError("RoARM M1 embodiment must expose five joint target ranges.")
        }
        return try sortedSignals.map { signal in
            guard let range = signal.range else {
                throw ValidationError("Embodiment joint target signal \(signal.id) is missing a range.")
            }
            return range.min...range.max
        }
    }

    private func safeCommissioningLimits(within modelLimits: [ClosedRange<Double>]) throws -> [ClosedRange<Double>] {
        guard modelLimits.count == RoArmM1ServoCommandEncoder.jointCount else {
            throw ValidationError("RoARM M1 embodiment must expose five joint target ranges.")
        }
        return try zip(RoArmM1ServoCommandEncoder.safeCommissioningJointLimits, modelLimits)
            .enumerated()
            .map { index, pair in
                let lower = max(pair.0.lowerBound, pair.1.lowerBound)
                let upper = min(pair.0.upperBound, pair.1.upperBound)
                guard lower <= upper else {
                    throw ValidationError("Safe commissioning range does not overlap joint \(index + 1) model range.")
                }
                return lower...upper
            }
    }

    private func validateCalibrationReport(path: String, loaded: LoadedKuyuRobot) throws {
        do {
            _ = try RoArmM1HardwareParityReadinessService().validateReport(
                path: path,
                body: loaded.body,
                world: loaded.world,
                embodiment: loaded.embodiment,
                compatibilityReport: loaded.compatibilityReport
            )
        } catch {
            throw ValidationError("Hardware calibration report validation failed: \(error)")
        }
        print("[roarm-m1] calibrationReport=\(path)")
        print("[roarm-m1] hardwareParity=validated")
    }

    private func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private func format(_ values: [Double]) -> String {
        "[" + values.map { String(format: "%.6f", $0) }.joined(separator: ", ") + "]"
    }
}

private enum RoArmM1SerialWriter {
    enum SerialError: Error, CustomStringConvertible {
        case openFailed(String, Int32)
        case configureFailed(String, Int32)
        case writeFailed(expected: Int, actual: Int)
        case drainFailed(Int32)

        var description: String {
            switch self {
            case .openFailed(let path, let code):
                return "open-failed path=\(path) errno=\(code)"
            case .configureFailed(let operation, let code):
                return "configure-failed operation=\(operation) errno=\(code)"
            case .writeFailed(let expected, let actual):
                return "write-failed expected=\(expected) actual=\(actual)"
            case .drainFailed(let code):
                return "drain-failed errno=\(code)"
            }
        }
    }

    static func write(data: Data, to path: String) throws {
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY)
        guard fd >= 0 else {
            throw SerialError.openFailed(path, errno)
        }
        defer {
            Darwin.close(fd)
        }

        var options = termios()
        guard tcgetattr(fd, &options) == 0 else {
            throw SerialError.configureFailed("tcgetattr", errno)
        }
        cfmakeraw(&options)
        guard cfsetspeed(&options, speed_t(B115200)) == 0 else {
            throw SerialError.configureFailed("cfsetspeed", errno)
        }
        options.c_cflag |= tcflag_t(CLOCAL)
        options.c_cflag |= tcflag_t(CREAD)
        options.c_cflag &= ~tcflag_t(CSTOPB)
        options.c_cflag &= ~tcflag_t(PARENB)
        options.c_cflag &= ~tcflag_t(CSIZE)
        options.c_cflag |= tcflag_t(CS8)
        guard tcsetattr(fd, TCSANOW, &options) == 0 else {
            throw SerialError.configureFailed("tcsetattr", errno)
        }

        let written = data.withUnsafeBytes { buffer -> Int in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return Darwin.write(fd, baseAddress, buffer.count)
        }
        guard written == data.count else {
            throw SerialError.writeFailed(expected: data.count, actual: written)
        }
        guard tcdrain(fd) == 0 else {
            throw SerialError.drainFailed(errno)
        }
    }
}
