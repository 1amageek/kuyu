import simd
import Testing
@testable import kuyu

@Test(.timeLimit(.minutes(1))) func quadrotorDerivativeHoverAccelerationIsZero() async throws {
    let params = QuadrotorParameters.baseline
    let state = try QuadrotorState(
        position: SIMD3<Double>(repeating: 0),
        velocity: SIMD3<Double>(repeating: 0),
        orientation: simd_quatd(angle: 0, axis: SIMD3<Double>(0, 0, 1)),
        angularVelocity: SIMD3<Double>(repeating: 0)
    )

    let hoverForce = SIMD3<Double>(0, 0, params.mass * params.gravity)
    let input = QuadrotorInput(bodyForce: hoverForce, bodyTorque: SIMD3<Double>(repeating: 0), worldForce: SIMD3<Double>(repeating: 0))
    let derivative = QuadrotorDynamics.derivative(
        state: state,
        input: input,
        parameters: params,
        gravity: params.gravity
    )

    #expect(simd_length(derivative.velocity) < 1e-9)
    #expect(simd_length(derivative.angularVelocity) == 0)
}
