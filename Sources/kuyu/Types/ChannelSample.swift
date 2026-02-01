import Foundation

public struct ChannelSample: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFiniteValue
        case nonFiniteTimestamp
        case negativeTimestamp
    }

    public let channelIndex: UInt32
    public let value: Double
    public let timestamp: TimeInterval

    public init(channelIndex: UInt32, value: Double, timestamp: TimeInterval) throws {
        guard value.isFinite else { throw ValidationError.nonFiniteValue }
        guard timestamp.isFinite else { throw ValidationError.nonFiniteTimestamp }
        guard timestamp >= 0 else { throw ValidationError.negativeTimestamp }

        self.channelIndex = channelIndex
        self.value = value
        self.timestamp = timestamp
    }
}

