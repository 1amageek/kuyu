import Foundation

public struct SimulationConfig: Sendable, Codable, Equatable {
    public let scenario: ScenarioConfig
    public let schedule: SimulationSchedule
    public let determinism: DeterminismConfig
    public let environment: WorldEnvironment

    public init(
        scenario: ScenarioConfig,
        schedule: SimulationSchedule,
        determinism: DeterminismConfig,
        environment: WorldEnvironment = .standard
    ) {
        self.scenario = scenario
        self.schedule = schedule
        self.determinism = determinism
        self.environment = environment
    }
}
