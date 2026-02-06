import KuyuCore

/// Extended evaluation wrapping the base `ScenarioEvaluation` with additional
/// control quality and inverse dynamics metrics.
public struct ExtendedScenarioEvaluation: Sendable, Codable, Equatable {

    /// The base safety evaluation (omega, tilt, recovery, etc.).
    public let base: ScenarioEvaluation

    /// Control quality metrics (tracking accuracy, effort, smoothness).
    public let controlQuality: ControlQualityMetrics?

    /// Inverse dynamics validation (physical plausibility of actions).
    public let inverseDynamics: InverseDynamicsValidation?

    public init(
        base: ScenarioEvaluation,
        controlQuality: ControlQualityMetrics?,
        inverseDynamics: InverseDynamicsValidation?
    ) {
        self.base = base
        self.controlQuality = controlQuality
        self.inverseDynamics = inverseDynamics
    }
}
