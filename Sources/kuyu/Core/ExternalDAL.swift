public protocol ExternalDAL {
    mutating func update(
        drives: [DriveIntent],
        telemetry: ExternalDALTelemetry,
        time: WorldTime
    ) throws -> [ActuatorCommand]
}
