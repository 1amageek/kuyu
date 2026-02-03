import Foundation

public struct WorldTime: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFinite
        case negative
    }

    public let stepIndex: UInt64
    public let time: TimeInterval

    public init(stepIndex: UInt64, time: TimeInterval) throws {
        guard time.isFinite else { throw ValidationError.nonFinite }
        guard time >= 0 else { throw ValidationError.negative }

        self.stepIndex = stepIndex
        self.time = time
    }

    public func advanced(by delta: TimeInterval) throws -> WorldTime {
        try WorldTime(stepIndex: stepIndex + 1, time: time + delta)
    }
}

