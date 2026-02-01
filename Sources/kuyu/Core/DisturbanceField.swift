public protocol DisturbanceField: Sendable {
    mutating func update(time: WorldTime) throws
}

