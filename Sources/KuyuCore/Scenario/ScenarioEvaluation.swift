public struct ScenarioEvaluation: Sendable, Codable, Equatable {
    public let scenarioId: ScenarioID
    public let seed: ScenarioSeed
    public let passed: Bool
    public let maxOmega: Double
    public let maxTiltDegrees: Double
    public let sustainedViolationSeconds: Double
    public let recoveryTimeSeconds: Double?
    public let overshootDegrees: Double?
    public let hfStabilityScore: Double?
    public let failures: [String]

    public init(
        scenarioId: ScenarioID,
        seed: ScenarioSeed,
        passed: Bool,
        maxOmega: Double,
        maxTiltDegrees: Double,
        sustainedViolationSeconds: Double,
        recoveryTimeSeconds: Double?,
        overshootDegrees: Double?,
        hfStabilityScore: Double?,
        failures: [String]
    ) {
        self.scenarioId = scenarioId
        self.seed = seed
        self.passed = passed
        self.maxOmega = maxOmega
        self.maxTiltDegrees = maxTiltDegrees
        self.sustainedViolationSeconds = sustainedViolationSeconds
        self.recoveryTimeSeconds = recoveryTimeSeconds
        self.overshootDegrees = overshootDegrees
        self.hfStabilityScore = hfStabilityScore
        self.failures = failures
    }
}
