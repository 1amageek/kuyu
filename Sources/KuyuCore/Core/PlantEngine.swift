public protocol PlantEngine {
    mutating func integrate(time: WorldTime) throws
    func snapshot() -> PlantStateSnapshot
    func safetyTrace() -> SafetyTrace
}
