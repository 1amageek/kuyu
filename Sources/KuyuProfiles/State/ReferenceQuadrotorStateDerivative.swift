import simd
import KuyuCore

public struct ReferenceQuadrotorStateDerivative: Sendable, Equatable {
    public var position: SIMD3<Double>
    public var velocity: SIMD3<Double>
    public var orientation: SIMD4<Double>
    public var angularVelocity: SIMD3<Double>

    public init(
        position: SIMD3<Double>,
        velocity: SIMD3<Double>,
        orientation: SIMD4<Double>,
        angularVelocity: SIMD3<Double>
    ) {
        self.position = position
        self.velocity = velocity
        self.orientation = orientation
        self.angularVelocity = angularVelocity
    }

    public static let zero = ReferenceQuadrotorStateDerivative(
        position: SIMD3<Double>(repeating: 0),
        velocity: SIMD3<Double>(repeating: 0),
        orientation: SIMD4<Double>(repeating: 0),
        angularVelocity: SIMD3<Double>(repeating: 0)
    )
}
