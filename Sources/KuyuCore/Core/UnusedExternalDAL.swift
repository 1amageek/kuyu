public struct UnusedExternalDAL: ExternalDAL {
    public enum DalError: Error, Equatable {
        case unexpectedCall
    }

    public init() {}

    public mutating func update(
        drives: [DriveIntent],
        corrections: [ReflexCorrection],
        telemetry: ExternalDALTelemetry,
        time: WorldTime
    ) throws -> [ActuatorCommand] {
        _ = drives
        _ = corrections
        _ = telemetry
        _ = time
        throw DalError.unexpectedCall
    }
}
