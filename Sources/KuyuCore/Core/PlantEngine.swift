public protocol PlantEngine {
    mutating func integrate(time: WorldTime) throws
}
