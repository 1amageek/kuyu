import KuyuCore

/// Control quality metrics analogous to Micro-World's PSNR/FVD.
///
/// Measures tracking accuracy, steady-state performance, control effort,
/// and smoothness — providing a complete picture of control quality
/// beyond safety envelope compliance.
public struct ControlQualityMetrics: Sendable, Codable, Equatable {

    /// Root-mean-square tracking error over the entire run.
    public let rmsTrackingError: Double

    /// Peak instantaneous tracking error.
    public let maxTrackingError: Double

    /// Mean error in the last 20% of the run (steady-state accuracy).
    public let steadyStateError: Double

    /// Time to first enter and remain within 2% of the target (seconds).
    public let settlingTime: Double?

    /// Time from 10% to 90% of a step response (seconds).
    public let riseTime: Double?

    /// Peak overshoot relative to the target value (percentage).
    public let percentOvershoot: Double?

    /// Integral of squared actuator output: ∫|u|²dt (energy consumption).
    public let controlEffort: Double

    /// Integral of squared actuator rate-of-change: ∫|du/dt|²dt (smoothness penalty).
    public let smoothness: Double

    public init(
        rmsTrackingError: Double,
        maxTrackingError: Double,
        steadyStateError: Double,
        settlingTime: Double?,
        riseTime: Double?,
        percentOvershoot: Double?,
        controlEffort: Double,
        smoothness: Double
    ) {
        self.rmsTrackingError = rmsTrackingError
        self.maxTrackingError = maxTrackingError
        self.steadyStateError = steadyStateError
        self.settlingTime = settlingTime
        self.riseTime = riseTime
        self.percentOvershoot = percentOvershoot
        self.controlEffort = controlEffort
        self.smoothness = smoothness
    }
}
