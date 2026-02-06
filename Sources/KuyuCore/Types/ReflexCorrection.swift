public struct ReflexCorrection: Hashable, Sendable, Codable {
    public enum ValidationError: Error, Equatable {
        case nonFinite
        case outOfRange(String)
    }

    public let driveIndex: DriveIndex
    public let clampMultiplier: Double
    public let damping: Double
    public let delta: Double

    public var primitiveIndex: DriveIndex { driveIndex }

    public init(
        driveIndex: DriveIndex,
        clampMultiplier: Double,
        damping: Double,
        delta: Double
    ) throws {
        guard clampMultiplier.isFinite, damping.isFinite, delta.isFinite else {
            throw ValidationError.nonFinite
        }
        guard clampMultiplier >= 0.0, clampMultiplier <= 1.0 else {
            throw ValidationError.outOfRange("clampMultiplier")
        }
        guard damping >= 0.0, damping <= 1.0 else {
            throw ValidationError.outOfRange("damping")
        }

        self.driveIndex = driveIndex
        self.clampMultiplier = clampMultiplier
        self.damping = damping
        self.delta = delta
    }
}
