import simd
import KuyuCore

public struct ReferenceQuadrotorDynamics: Sendable {
    public static func derivative(
        state: ReferenceQuadrotorState,
        input: ReferenceQuadrotorInput,
        parameters: ReferenceQuadrotorParameters,
        gravity: Double
    ) -> ReferenceQuadrotorStateDerivative {
        let gravityWorld = SIMD3<Double>(0, 0, -gravity)
        let inertia = parameters.inertiaSIMD

        let forceWorld = state.orientation.act(input.bodyForce) + input.worldForce
        let acceleration = (forceWorld / parameters.mass) + gravityWorld

        let inertiaOmega = inertia * state.angularVelocity
        let gyro = simd_cross(state.angularVelocity, inertiaOmega)
        let angularAccel = (input.bodyTorque - gyro) / inertia

        let omegaQuat = simd_quatd(real: 0, imag: state.angularVelocity)
        let qDot = (state.orientation * omegaQuat).vector * 0.5

        return ReferenceQuadrotorStateDerivative(
            position: state.velocity,
            velocity: acceleration,
            orientation: qDot,
            angularVelocity: angularAccel
        )
    }

    public static func integrateRK4(
        state: ReferenceQuadrotorState,
        input: ReferenceQuadrotorInput,
        parameters: ReferenceQuadrotorParameters,
        gravity: Double,
        delta: Double
    ) -> ReferenceQuadrotorState {
        let k1 = derivative(state: state, input: input, parameters: parameters, gravity: gravity)
        let s2 = state.applying(derivative: k1, scale: delta * 0.5)
        let k2 = derivative(state: s2, input: input, parameters: parameters, gravity: gravity)
        let s3 = state.applying(derivative: k2, scale: delta * 0.5)
        let k3 = derivative(state: s3, input: input, parameters: parameters, gravity: gravity)
        let s4 = state.applying(derivative: k3, scale: delta)
        let k4 = derivative(state: s4, input: input, parameters: parameters, gravity: gravity)

        let position = state.position + (k1.position + k2.position * 2 + k3.position * 2 + k4.position) * (delta / 6)
        let velocity = state.velocity + (k1.velocity + k2.velocity * 2 + k3.velocity * 2 + k4.velocity) * (delta / 6)
        let orientationVector = state.orientation.vector + (k1.orientation + k2.orientation * 2 + k3.orientation * 2 + k4.orientation) * (delta / 6)
        let angularVelocity = state.angularVelocity + (k1.angularVelocity + k2.angularVelocity * 2 + k3.angularVelocity * 2 + k4.angularVelocity) * (delta / 6)

        let orientation = simd_quatd(vector: orientationVector).normalizedQuat

        return ReferenceQuadrotorState(
            uncheckedPosition: position,
            uncheckedVelocity: velocity,
            uncheckedOrientation: orientation,
            uncheckedAngularVelocity: angularVelocity
        )
    }

    public static func specificForceBody(
        state: ReferenceQuadrotorState,
        input: ReferenceQuadrotorInput,
        parameters: ReferenceQuadrotorParameters,
        gravity: Double
    ) -> SIMD3<Double> {
        let gravityWorld = SIMD3<Double>(0, 0, -gravity)
        let forceWorld = state.orientation.act(input.bodyForce) + input.worldForce
        let acceleration = (forceWorld / parameters.mass) + gravityWorld
        let withoutGravity = acceleration - gravityWorld
        return state.orientation.inverse.act(withoutGravity)
    }
}
