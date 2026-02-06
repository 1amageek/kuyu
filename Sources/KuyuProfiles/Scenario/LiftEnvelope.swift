import KuyuCore

public struct LiftEnvelope: Sendable, Codable, Equatable {
    public let targetZ: Double
    public let tolerance: Double
    public let maxVelocity: Double
    public let warmupTime: Double
    public let requiredHoldTime: Double

    public init(
        targetZ: Double,
        tolerance: Double,
        maxVelocity: Double,
        warmupTime: Double,
        requiredHoldTime: Double
    ) {
        self.targetZ = targetZ
        self.tolerance = tolerance
        self.maxVelocity = maxVelocity
        self.warmupTime = warmupTime
        self.requiredHoldTime = requiredHoldTime
    }
}
