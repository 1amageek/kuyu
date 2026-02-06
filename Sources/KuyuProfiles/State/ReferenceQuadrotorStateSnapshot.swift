import KuyuCore

public struct ReferenceQuadrotorStateSnapshot: Sendable, Codable, Equatable {
    public let position: Axis3
    public let velocity: Axis3
    public let orientation: QuaternionSnapshot
    public let angularVelocity: Axis3

    public init(
        position: Axis3,
        velocity: Axis3,
        orientation: QuaternionSnapshot,
        angularVelocity: Axis3
    ) {
        self.position = position
        self.velocity = velocity
        self.orientation = orientation
        self.angularVelocity = angularVelocity
    }

    public init(state: ReferenceQuadrotorState) {
        self.position = Axis3(x: state.position.x, y: state.position.y, z: state.position.z)
        self.velocity = Axis3(x: state.velocity.x, y: state.velocity.y, z: state.velocity.z)
        self.orientation = QuaternionSnapshot(orientation: state.orientation)
        self.angularVelocity = Axis3(
            x: state.angularVelocity.x,
            y: state.angularVelocity.y,
            z: state.angularVelocity.z
        )
    }
}
