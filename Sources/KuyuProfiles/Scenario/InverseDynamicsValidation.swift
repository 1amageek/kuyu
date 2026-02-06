import KuyuCore

/// Validates controller actions using inverse dynamics, analogous to Micro-World's IDM metric.
///
/// An inverse dynamics model predicts what actuator values should produce the observed
/// state transitions. High agreement between predicted and actual actions indicates
/// that the controller is physically plausible and controllable.
public struct InverseDynamicsValidation: Sendable, Codable, Equatable {

    /// Pearson correlation between IDM-predicted and actual actuator values.
    /// Range: [-1, 1]. Higher is better.
    public let idmCorrelation: Double

    /// Mean squared error between IDM-predicted and actual actuator values.
    public let idmMSE: Double

    /// Fraction of timesteps where actuator values are within physically plausible bounds.
    /// Range: [0, 1]. Higher is better.
    public let physicallyPlausibleRatio: Double

    public init(
        idmCorrelation: Double,
        idmMSE: Double,
        physicallyPlausibleRatio: Double
    ) {
        self.idmCorrelation = idmCorrelation
        self.idmMSE = idmMSE
        self.physicallyPlausibleRatio = physicallyPlausibleRatio
    }
}
