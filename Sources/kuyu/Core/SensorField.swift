public protocol SensorField: Sendable {
    mutating func sample(time: WorldTime) throws -> [ChannelSample]
}

