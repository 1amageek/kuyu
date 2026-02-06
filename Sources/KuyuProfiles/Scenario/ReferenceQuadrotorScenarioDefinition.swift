import KuyuCore

public struct ReferenceQuadrotorScenarioDefinition: Sendable, Codable, Equatable {
    public let config: ScenarioConfig
    public let kind: ReferenceQuadrotorScenarioKind
    public let initialPosition: Axis3
    public let initialAttitude: EulerAngles
    public let initialAngularVelocity: Axis3
    public let safetyEnvelope: SafetyEnvelope
    public let liftEnvelope: LiftEnvelope?
    public let torqueEvents: [TorqueDisturbanceEvent]
    public let actuatorDegradation: ActuatorDegradation?
    public let gyroDriftScale: Double
    public let swapEvents: [SwapEvent]
    public let hfEvents: [HFStressEvent]

    public init(
        config: ScenarioConfig,
        kind: ReferenceQuadrotorScenarioKind,
        initialPosition: Axis3,
        initialAttitude: EulerAngles,
        initialAngularVelocity: Axis3,
        safetyEnvelope: SafetyEnvelope,
        liftEnvelope: LiftEnvelope? = nil,
        torqueEvents: [TorqueDisturbanceEvent],
        actuatorDegradation: ActuatorDegradation?,
        gyroDriftScale: Double,
        swapEvents: [SwapEvent],
        hfEvents: [HFStressEvent]
    ) {
        self.config = config
        self.kind = kind
        self.initialPosition = initialPosition
        self.initialAttitude = initialAttitude
        self.initialAngularVelocity = initialAngularVelocity
        self.safetyEnvelope = safetyEnvelope
        self.liftEnvelope = liftEnvelope
        self.torqueEvents = torqueEvents
        self.actuatorDegradation = actuatorDegradation
        self.gyroDriftScale = gyroDriftScale
        self.swapEvents = swapEvents
        self.hfEvents = hfEvents
    }
}
