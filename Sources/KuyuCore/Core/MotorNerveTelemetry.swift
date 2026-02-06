public struct MotorNerveTelemetry: Sendable, Codable, Equatable {
    public let actuatorTelemetry: ActuatorTelemetrySnapshot
    public let failsafeActive: Bool

    public init(actuatorTelemetry: ActuatorTelemetrySnapshot, failsafeActive: Bool = false) {
        self.actuatorTelemetry = actuatorTelemetry
        self.failsafeActive = failsafeActive
    }
}
