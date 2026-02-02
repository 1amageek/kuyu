public protocol CutInterface {
    mutating func update(samples: [ChannelSample], time: WorldTime) throws -> CutOutput
}
