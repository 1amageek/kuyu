public struct SimulationLog: Sendable, Codable, Equatable {
    public let scenarioId: ScenarioID
    public let seed: ScenarioSeed
    public let timeStep: TimeStep
    public let determinism: DeterminismConfig
    public let configHash: String
    public let events: [WorldStepLog]
    public let failureReason: FailureReason?
    public let failureTime: Double?

    public init(
        scenarioId: ScenarioID,
        seed: ScenarioSeed,
        timeStep: TimeStep,
        determinism: DeterminismConfig,
        configHash: String,
        events: [WorldStepLog],
        failureReason: FailureReason? = nil,
        failureTime: Double? = nil
    ) {
        self.scenarioId = scenarioId
        self.seed = seed
        self.timeStep = timeStep
        self.determinism = determinism
        self.configHash = configHash
        self.events = events
        self.failureReason = failureReason
        self.failureTime = failureTime
    }
}
