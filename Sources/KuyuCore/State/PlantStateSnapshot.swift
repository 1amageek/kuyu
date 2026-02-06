public struct PlantStateSnapshot: Sendable, Codable, Equatable {
    public let root: RigidBodySnapshot
    public let bodies: [RigidBodySnapshot]
    public let scalars: [String: Double]

    public init(
        root: RigidBodySnapshot,
        bodies: [RigidBodySnapshot] = [],
        scalars: [String: Double] = [:]
    ) {
        self.root = root
        self.bodies = bodies
        self.scalars = scalars
    }
}
