import KuyuCore

public struct ReplayResiduals: Sendable, Codable, Equatable {
    public let position: Double
    public let velocity: Double
    public let angularVelocity: Double
    public let quaternionResidual: Double
    public let motorThrust: Double
    public let sensor: Double

    public init(
        position: Double,
        velocity: Double,
        angularVelocity: Double,
        quaternionResidual: Double,
        motorThrust: Double,
        sensor: Double
    ) {
        self.position = position
        self.velocity = velocity
        self.angularVelocity = angularVelocity
        self.quaternionResidual = quaternionResidual
        self.motorThrust = motorThrust
        self.sensor = sensor
    }

    public static let zero = ReplayResiduals(
        position: 0,
        velocity: 0,
        angularVelocity: 0,
        quaternionResidual: 0,
        motorThrust: 0,
        sensor: 0
    )
}
