import Foundation

public struct TimeStep: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFinite
        case nonPositive
    }

    public let delta: TimeInterval

    public init(delta: TimeInterval) throws {
        guard delta.isFinite else { throw ValidationError.nonFinite }
        guard delta > 0 else { throw ValidationError.nonPositive }
        self.delta = delta
    }
}

