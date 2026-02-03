import simd
import Testing
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func actuatorEngineClampsToMaxThrust() async throws {
    let params = QuadrotorParameters.baseline
    let state = try QuadrotorState(
        position: .zero,
        velocity: .zero,
        orientation: .init(angle: 0, axis: SIMD3<Double>(0, 0, 1)),
        angularVelocity: .zero
    )
    let store = WorldStore(state: state, motorThrusts: try MotorThrusts.uniform(0))
    let timeStep = try TimeStep(delta: 0.01)
    let maxThrusts = try MotorMaxThrusts.uniform(2.0)

    var engine = QuadrotorActuatorEngine(
        parameters: params,
        store: store,
        timeStep: timeStep,
        motorMaxThrusts: maxThrusts
    )

    let commands = try [
        ActuatorCommand(index: ActuatorIndex(0), value: 10),
        ActuatorCommand(index: ActuatorIndex(1), value: 10),
        ActuatorCommand(index: ActuatorIndex(2), value: 10),
        ActuatorCommand(index: ActuatorIndex(3), value: 10)
    ]

    try engine.apply(commands: commands, time: try WorldTime(stepIndex: 0, time: 0.0))
    try engine.update(time: try WorldTime(stepIndex: 1, time: 0.01))

    #expect(store.motorThrusts.f1 <= 2.0)
    #expect(store.motorThrusts.f2 <= 2.0)
    #expect(store.motorThrusts.f3 <= 2.0)
    #expect(store.motorThrusts.f4 <= 2.0)
}
