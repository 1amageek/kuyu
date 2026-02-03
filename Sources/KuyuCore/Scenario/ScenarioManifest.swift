public struct ScenarioManifest: Sendable, Codable, Equatable {
    public let scenarioId: ScenarioID
    public let seed: ScenarioSeed
    public let kind: ScenarioKind
    public let duration: Double
    public let timeStep: TimeStep
    public let torqueEvents: [TorqueDisturbanceEvent]
    public let actuatorDegradation: ActuatorDegradation?
    public let gyroDriftScale: Double
    public let swapEvents: [SwapEvent]
    public let hfEvents: [HFStressEvent]

    public init(
        scenarioId: ScenarioID,
        seed: ScenarioSeed,
        kind: ScenarioKind,
        duration: Double,
        timeStep: TimeStep,
        torqueEvents: [TorqueDisturbanceEvent],
        actuatorDegradation: ActuatorDegradation?,
        gyroDriftScale: Double,
        swapEvents: [SwapEvent],
        hfEvents: [HFStressEvent]
    ) {
        self.scenarioId = scenarioId
        self.seed = seed
        self.kind = kind
        self.duration = duration
        self.timeStep = timeStep
        self.torqueEvents = torqueEvents
        self.actuatorDegradation = actuatorDegradation
        self.gyroDriftScale = gyroDriftScale
        self.swapEvents = swapEvents
        self.hfEvents = hfEvents
    }
}
