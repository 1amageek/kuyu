import KuyuCore

public struct UnusedMotorNerve: MotorNerveEndpoint {
    public enum MotorNerveError: Error, Equatable {
        case unexpectedCall
    }

    public init() {}

    public mutating func update(
        input drives: [DriveIntent],
        corrections: [ReflexCorrection],
        telemetry: MotorNerveTelemetry,
        time: WorldTime
    ) throws -> [ActuatorValue] {
        _ = drives
        _ = corrections
        _ = telemetry
        _ = time
        throw MotorNerveError.unexpectedCall
    }
}
