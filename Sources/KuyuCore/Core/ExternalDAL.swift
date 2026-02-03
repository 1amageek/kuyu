public protocol ExternalDAL {
    mutating func update(
        drives: [DriveIntent],
        corrections: [ReflexCorrection],
        telemetry: ExternalDALTelemetry,
        time: WorldTime
    ) throws -> [ActuatorCommand]
}
