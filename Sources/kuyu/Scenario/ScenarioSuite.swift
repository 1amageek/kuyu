public protocol ScenarioSuite: Sendable {
    func scenarios() throws -> [ScenarioDefinition]
}
