import simd
import KuyuCore

public struct ReferenceQuadrotorInput: Sendable, Equatable {
    public var bodyForce: SIMD3<Double>
    public var bodyTorque: SIMD3<Double>
    public var worldForce: SIMD3<Double>

    public init(bodyForce: SIMD3<Double>, bodyTorque: SIMD3<Double>, worldForce: SIMD3<Double>) {
        self.bodyForce = bodyForce
        self.bodyTorque = bodyTorque
        self.worldForce = worldForce
    }
}
