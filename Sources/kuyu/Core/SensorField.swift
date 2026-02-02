public protocol SensorField {
    mutating func sample(time: WorldTime) throws -> [ChannelSample]
}
