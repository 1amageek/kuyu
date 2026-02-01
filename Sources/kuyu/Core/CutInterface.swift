public protocol CutInterface: Sendable {
    mutating func update(samples: [ChannelSample], time: WorldTime) throws -> CutOutput
}

