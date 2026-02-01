public struct ScenarioManifest: Sendable, Codable, Equatable {
    public let scenarioId: ScenarioID
    public let seed: ScenarioSeed
    public let kind: ScenarioKind
    public let duration: Double
    public let timeStep: TimeStep

    public init(
        scenarioId: ScenarioID,
        seed: ScenarioSeed,
        kind: ScenarioKind,
        duration: Double,
        timeStep: TimeStep
    ) {
        self.scenarioId = scenarioId
        self.seed = seed
        self.kind = kind
        self.duration = duration
        self.timeStep = timeStep
    }
}
