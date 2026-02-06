import simd
import KuyuCore

public struct ReferenceQuadrotorState: Sendable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
    }

    public var position: SIMD3<Double>
    public var velocity: SIMD3<Double>
    public var orientation: simd_quatd
    public var angularVelocity: SIMD3<Double>

    public init(
        position: SIMD3<Double>,
        velocity: SIMD3<Double>,
        orientation: simd_quatd,
        angularVelocity: SIMD3<Double>
    ) throws {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
            throw ValidationError.nonFinite("position")
        }
        guard velocity.x.isFinite, velocity.y.isFinite, velocity.z.isFinite else {
            throw ValidationError.nonFinite("velocity")
        }
        guard orientation.vector.x.isFinite,
              orientation.vector.y.isFinite,
              orientation.vector.z.isFinite,
              orientation.vector.w.isFinite else {
            throw ValidationError.nonFinite("orientation")
        }
        guard angularVelocity.x.isFinite, angularVelocity.y.isFinite, angularVelocity.z.isFinite else {
            throw ValidationError.nonFinite("angularVelocity")
        }

        self.position = position
        self.velocity = velocity
        self.orientation = orientation.normalizedQuat
        self.angularVelocity = angularVelocity
    }

    public func normalized() -> ReferenceQuadrotorState {
        ReferenceQuadrotorState(
            uncheckedPosition: position,
            uncheckedVelocity: velocity,
            uncheckedOrientation: orientation.normalizedQuat,
            uncheckedAngularVelocity: angularVelocity
        )
    }

    public func applying(derivative: ReferenceQuadrotorStateDerivative, scale: Double) -> ReferenceQuadrotorState {
        let positionNext = position + derivative.position * scale
        let velocityNext = velocity + derivative.velocity * scale
        let orientationVector = orientation.vector + derivative.orientation * scale
        let orientationNext = simd_quatd(vector: orientationVector).normalizedQuat
        let angularNext = angularVelocity + derivative.angularVelocity * scale

        return ReferenceQuadrotorState(
            uncheckedPosition: positionNext,
            uncheckedVelocity: velocityNext,
            uncheckedOrientation: orientationNext,
            uncheckedAngularVelocity: angularNext
        )
    }

    init(
        uncheckedPosition: SIMD3<Double>,
        uncheckedVelocity: SIMD3<Double>,
        uncheckedOrientation: simd_quatd,
        uncheckedAngularVelocity: SIMD3<Double>
    ) {
        self.position = uncheckedPosition
        self.velocity = uncheckedVelocity
        self.orientation = uncheckedOrientation
        self.angularVelocity = uncheckedAngularVelocity
    }
}
