public protocol ActuatorEngine {
    mutating func update(time: WorldTime) throws
    mutating func apply(values: [ActuatorValue], time: WorldTime) throws
    func telemetrySnapshot() -> ActuatorTelemetrySnapshot
}
