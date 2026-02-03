public struct ScenarioLogIndex: Sendable, Codable, Equatable {
    public let scenarioId: ScenarioID
    public let seed: ScenarioSeed
    public let fileName: String

    public init(scenarioId: ScenarioID, seed: ScenarioSeed, fileName: String) {
        self.scenarioId = scenarioId
        self.seed = seed
        self.fileName = fileName
    }
}
