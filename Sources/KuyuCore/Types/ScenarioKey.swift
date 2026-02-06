public struct ScenarioKey: Hashable, Sendable, Codable {
    public let scenarioId: ScenarioID
    public let seed: ScenarioSeed

    public init(scenarioId: ScenarioID, seed: ScenarioSeed) {
        self.scenarioId = scenarioId
        self.seed = seed
    }
}
