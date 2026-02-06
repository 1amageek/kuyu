public struct RigidBodySnapshot: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let position: Axis3
    public let velocity: Axis3
    public let orientation: QuaternionSnapshot
    public let angularVelocity: Axis3

    public init(
        id: String,
        position: Axis3,
        velocity: Axis3,
        orientation: QuaternionSnapshot,
        angularVelocity: Axis3
    ) {
        self.id = id
        self.position = position
        self.velocity = velocity
        self.orientation = orientation
        self.angularVelocity = angularVelocity
    }
}
