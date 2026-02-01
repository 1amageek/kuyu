public struct ScenarioDefinition: Sendable, Codable, Equatable {
    public let config: ScenarioConfig
    public let kind: ScenarioKind
    public let initialAttitude: EulerAngles
    public let initialAngularVelocity: Axis3
    public let safetyEnvelope: SafetyEnvelope
    public let torqueEvents: [TorqueDisturbanceEvent]
    public let actuatorDegradation: ActuatorDegradation?
    public let gyroDriftScale: Double

    public init(
        config: ScenarioConfig,
        kind: ScenarioKind,
        initialAttitude: EulerAngles,
        initialAngularVelocity: Axis3,
        safetyEnvelope: SafetyEnvelope,
        torqueEvents: [TorqueDisturbanceEvent],
        actuatorDegradation: ActuatorDegradation?,
        gyroDriftScale: Double
    ) {
        self.config = config
        self.kind = kind
        self.initialAttitude = initialAttitude
        self.initialAngularVelocity = initialAngularVelocity
        self.safetyEnvelope = safetyEnvelope
        self.torqueEvents = torqueEvents
        self.actuatorDegradation = actuatorDegradation
        self.gyroDriftScale = gyroDriftScale
    }
}
