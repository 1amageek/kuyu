public struct UnusedExternalDAL: ExternalDAL {
    public enum DalError: Error, Equatable {
        case unexpectedCall
    }

    public init() {}

    public mutating func update(
        drives: [DriveIntent],
        telemetry: ExternalDALTelemetry,
        time: WorldTime
    ) throws -> [ActuatorCommand] {
        _ = drives
        _ = telemetry
        _ = time
        throw DalError.unexpectedCall
    }
}
