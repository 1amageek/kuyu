import KuyuCore

public struct ReplayCheckResult: Sendable, Codable, Equatable {
    public let scenarioId: ScenarioID
    public let seed: ScenarioSeed
    public let tier: DeterminismTier
    public let passed: Bool
    public let issues: [String]
    public let residuals: ReplayResiduals

    public init(
        scenarioId: ScenarioID,
        seed: ScenarioSeed,
        tier: DeterminismTier,
        passed: Bool,
        issues: [String],
        residuals: ReplayResiduals
    ) {
        self.scenarioId = scenarioId
        self.seed = seed
        self.tier = tier
        self.passed = passed
        self.issues = issues
        self.residuals = residuals
    }
}
