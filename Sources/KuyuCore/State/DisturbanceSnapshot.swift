public struct DisturbanceSnapshot: Sendable, Codable, Equatable {
    public let forceWorld: Axis3
    public let torqueBody: Axis3

    public init(forceWorld: Axis3, torqueBody: Axis3) {
        self.forceWorld = forceWorld
        self.torqueBody = torqueBody
    }
}
