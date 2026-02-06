import KuyuCore

public struct ScenarioLogEntry: Sendable, Codable, Equatable {
    public let key: ScenarioKey
    public let log: SimulationLog

    public init(key: ScenarioKey, log: SimulationLog) {
        self.key = key
        self.log = log
    }
}
