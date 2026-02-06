import simd
import Testing
import KuyuProfiles
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func actuatorEngineClampsToMaxThrust() async throws {
    let params = ReferenceQuadrotorParameters.baseline
    let state = try ReferenceQuadrotorState(
        position: .zero,
        velocity: .zero,
        orientation: .init(angle: 0, axis: SIMD3<Double>(0, 0, 1)),
        angularVelocity: .zero
    )
    let store = ReferenceQuadrotorWorldStore(state: state, motorThrusts: try MotorThrusts.uniform(0))
    let timeStep = try TimeStep(delta: 0.01)
    let maxThrusts = try MotorMaxThrusts.uniform(2.0)

    var engine = ReferenceQuadrotorActuatorEngine(
        parameters: params,
        store: store,
        timeStep: timeStep,
        motorMaxThrusts: maxThrusts
    )

    let values = try [
        ActuatorValue(index: ActuatorIndex(0), value: 10),
        ActuatorValue(index: ActuatorIndex(1), value: 10),
        ActuatorValue(index: ActuatorIndex(2), value: 10),
        ActuatorValue(index: ActuatorIndex(3), value: 10)
    ]

    try engine.apply(values: values, time: try WorldTime(stepIndex: 0, time: 0.0))
    try engine.update(time: try WorldTime(stepIndex: 1, time: 0.01))

    #expect(store.motorThrusts.f1 <= 2.0)
    #expect(store.motorThrusts.f2 <= 2.0)
    #expect(store.motorThrusts.f3 <= 2.0)
    #expect(store.motorThrusts.f4 <= 2.0)
}
