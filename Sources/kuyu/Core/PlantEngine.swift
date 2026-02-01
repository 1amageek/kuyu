public protocol PlantEngine: Sendable {
    mutating func integrate(time: WorldTime) throws
}

