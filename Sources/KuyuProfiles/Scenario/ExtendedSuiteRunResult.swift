import KuyuCore

/// Extended suite run result combining base results with extended evaluations
/// and suite-level robustness statistics.
public struct ExtendedSuiteRunResult: Sendable, Codable, Equatable {

    /// The base suite run result (evaluations, replay checks, pass/fail).
    public let base: SuiteRunResult

    /// Per-scenario extended evaluations with control quality and IDM metrics.
    public let extendedEvaluations: [ExtendedScenarioEvaluation]

    /// Suite-level robustness statistics.
    public let robustness: RobustnessStatistics

    public init(
        base: SuiteRunResult,
        extendedEvaluations: [ExtendedScenarioEvaluation],
        robustness: RobustnessStatistics
    ) {
        self.base = base
        self.extendedEvaluations = extendedEvaluations
        self.robustness = robustness
    }
}
