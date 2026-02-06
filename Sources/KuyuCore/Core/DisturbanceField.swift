public protocol DisturbanceField {
    mutating func update(time: WorldTime) throws
    func snapshot() -> DisturbanceSnapshot
}
