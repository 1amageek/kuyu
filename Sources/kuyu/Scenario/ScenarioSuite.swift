public protocol ScenarioSuite {
    func scenarios() throws -> [ScenarioDefinition]
}
