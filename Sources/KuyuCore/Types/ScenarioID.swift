public struct ScenarioID: Sendable, Codable, Hashable {
    public enum ValidationError: Error, Equatable {
        case empty
    }

    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard !rawValue.isEmpty else { throw ValidationError.empty }
        self.rawValue = rawValue
    }
}

