public struct ScenarioSeed: Sendable, Codable, Hashable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

