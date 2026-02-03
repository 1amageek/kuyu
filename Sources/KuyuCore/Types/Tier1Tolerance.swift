public struct Tier1Tolerance: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case nonPositive(String)
    }

    public static let baseline: Tier1Tolerance = {
        do {
            return try Tier1Tolerance(
                position: 1e-4,
                velocity: 1e-4,
                angularVelocity: 1e-4,
                quaternionResidual: 1e-7,
                motorThrust: 1e-4,
                sensor: 1e-4
            )
        } catch {
            preconditionFailure("Invalid Tier1 baseline tolerances: \\(error)")
        }
    }()

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
    ) throws {
        guard position.isFinite else { throw ValidationError.nonFinite("position") }
        guard velocity.isFinite else { throw ValidationError.nonFinite("velocity") }
        guard angularVelocity.isFinite else { throw ValidationError.nonFinite("angularVelocity") }
        guard quaternionResidual.isFinite else { throw ValidationError.nonFinite("quaternionResidual") }
        guard motorThrust.isFinite else { throw ValidationError.nonFinite("motorThrust") }
        guard sensor.isFinite else { throw ValidationError.nonFinite("sensor") }

        guard position > 0 else { throw ValidationError.nonPositive("position") }
        guard velocity > 0 else { throw ValidationError.nonPositive("velocity") }
        guard angularVelocity > 0 else { throw ValidationError.nonPositive("angularVelocity") }
        guard quaternionResidual > 0 else { throw ValidationError.nonPositive("quaternionResidual") }
        guard motorThrust > 0 else { throw ValidationError.nonPositive("motorThrust") }
        guard sensor > 0 else { throw ValidationError.nonPositive("sensor") }

        self.position = position
        self.velocity = velocity
        self.angularVelocity = angularVelocity
        self.quaternionResidual = quaternionResidual
        self.motorThrust = motorThrust
        self.sensor = sensor
    }
}
