import KuyuCore

public protocol ReferenceQuadrotorScenarioSuite {
    func scenarios() throws -> [ReferenceQuadrotorScenarioDefinition]
}
