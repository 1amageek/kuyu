import simd
import Testing
import KuyuProfiles
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func quadrotorDerivativeHoverAccelerationIsZero() async throws {
    let params = ReferenceQuadrotorParameters.baseline
    let state = try ReferenceQuadrotorState(
        position: SIMD3<Double>(repeating: 0),
        velocity: SIMD3<Double>(repeating: 0),
        orientation: simd_quatd(angle: 0, axis: SIMD3<Double>(0, 0, 1)),
        angularVelocity: SIMD3<Double>(repeating: 0)
    )

    let hoverForce = SIMD3<Double>(0, 0, params.mass * params.gravity)
    let input = ReferenceQuadrotorInput(bodyForce: hoverForce, bodyTorque: SIMD3<Double>(repeating: 0), worldForce: SIMD3<Double>(repeating: 0))
    let derivative = ReferenceQuadrotorDynamics.derivative(
        state: state,
        input: input,
        parameters: params,
        gravity: params.gravity
    )

    #expect(simd_length(derivative.velocity) < 1e-9)
    #expect(simd_length(derivative.angularVelocity) == 0)
}

@Test(.timeLimit(.minutes(1))) func quadrotorIntegrateRK4AdvancesPositionWithConstantVelocity() async throws {
    let params = ReferenceQuadrotorParameters.baseline
    let state = try ReferenceQuadrotorState(
        position: SIMD3<Double>(repeating: 0),
        velocity: SIMD3<Double>(1, 0, 0),
        orientation: simd_quatd(angle: 0, axis: SIMD3<Double>(0, 0, 1)),
        angularVelocity: SIMD3<Double>(repeating: 0)
    )

    let input = ReferenceQuadrotorInput(bodyForce: .zero, bodyTorque: .zero, worldForce: .zero)
    let next = ReferenceQuadrotorDynamics.integrateRK4(
        state: state,
        input: input,
        parameters: params,
        gravity: 0.0,
        delta: 0.1
    )

    #expect(abs(next.position.x - 0.1) < 1e-9)
    #expect(abs(next.position.y) < 1e-9)
    #expect(abs(next.position.z) < 1e-9)
}

@Test(.timeLimit(.minutes(1))) func quadrotorSpecificForceBodyMatchesThrustPerMass() async throws {
    let params = ReferenceQuadrotorParameters.baseline
    let state = try ReferenceQuadrotorState(
        position: SIMD3<Double>(repeating: 0),
        velocity: SIMD3<Double>(repeating: 0),
        orientation: simd_quatd(angle: 0, axis: SIMD3<Double>(0, 0, 1)),
        angularVelocity: SIMD3<Double>(repeating: 0)
    )
    let bodyForce = SIMD3<Double>(0, 0, params.mass * params.gravity)
    let input = ReferenceQuadrotorInput(bodyForce: bodyForce, bodyTorque: .zero, worldForce: .zero)
    let specificForce = ReferenceQuadrotorDynamics.specificForceBody(
        state: state,
        input: input,
        parameters: params,
        gravity: params.gravity
    )

    #expect(abs(specificForce.z - params.gravity) < 1e-9)
    #expect(abs(specificForce.x) < 1e-9)
    #expect(abs(specificForce.y) < 1e-9)
}
