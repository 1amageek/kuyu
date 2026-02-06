public struct PlantInertialProperties: Sendable, Equatable {
    public let mass: Double
    public let inertia: Axis3

    public init(mass: Double, inertia: Axis3) {
        self.mass = mass
        self.inertia = inertia
    }
}
