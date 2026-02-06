import KuyuCore

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
    public let failureReason: FailureReason?
    public let failureTime: Double?

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
        failures: [String],
        failureReason: FailureReason? = nil,
        failureTime: Double? = nil
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
        self.failureReason = failureReason
        self.failureTime = failureTime
    }
}
