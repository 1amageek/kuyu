public struct SuiteRunResult: Sendable, Codable, Equatable {
    public let evaluations: [ScenarioEvaluation]
    public let replayChecks: [ReplayCheckResult]
    public let passed: Bool

    public init(
        evaluations: [ScenarioEvaluation],
        replayChecks: [ReplayCheckResult],
        passed: Bool
    ) {
        self.evaluations = evaluations
        self.replayChecks = replayChecks
        self.passed = passed
    }
}
