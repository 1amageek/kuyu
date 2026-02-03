public struct DeterminismConfig: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case missingTier1Tolerance
    }

    public let tier: DeterminismTier
    public let tier1Tolerance: Tier1Tolerance?

    public init(
        tier: DeterminismTier,
        tier1Tolerance: Tier1Tolerance? = nil
    ) throws {
        if tier == .tier1 && tier1Tolerance == nil {
            throw ValidationError.missingTier1Tolerance
        }
        self.tier = tier
        self.tier1Tolerance = tier1Tolerance
    }
}
