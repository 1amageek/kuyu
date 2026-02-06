import KuyuCore

/// Suite-level robustness statistics computed across multiple scenario evaluations.
///
/// Provides distribution-level metrics analogous to Micro-World's FVD
/// (Frechet Video Distance), measuring consistency and degradation margins
/// across seeds, scenario variants, and stress conditions.
public struct RobustnessStatistics: Sendable, Codable, Equatable {

    /// Fraction of scenarios that passed all criteria.
    public let passRate: Double

    /// Mean recovery time across scenarios that had recovery events (seconds).
    public let meanRecoveryTime: Double?

    /// Worst-case angular velocity observed across all runs (rad/s).
    public let worstCaseOmega: Double

    /// Worst-case tilt angle observed across all runs (degrees).
    public let worstCaseTilt: Double

    /// Consistency score: 1 - (σ/μ) of key metrics. Higher is more consistent.
    /// Range: [0, 1] when well-defined.
    public let consistencyScore: Double

    /// Performance degradation margin under stress vs baseline.
    /// 0 = no degradation, higher = worse under stress.
    public let degradationMargin: Double

    public init(
        passRate: Double,
        meanRecoveryTime: Double?,
        worstCaseOmega: Double,
        worstCaseTilt: Double,
        consistencyScore: Double,
        degradationMargin: Double
    ) {
        self.passRate = passRate
        self.meanRecoveryTime = meanRecoveryTime
        self.worstCaseOmega = worstCaseOmega
        self.worstCaseTilt = worstCaseTilt
        self.consistencyScore = consistencyScore
        self.degradationMargin = degradationMargin
    }
}
