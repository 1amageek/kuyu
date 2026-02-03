import simd
import Testing
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func imu6SensorReportsHoverAcceleration() async throws {
    let params = QuadrotorParameters.baseline
    let mixer = QuadrotorMixer(armLength: params.armLength, yawCoefficient: params.yawCoefficient)
    let state = try QuadrotorState(
        position: SIMD3<Double>(repeating: 0),
        velocity: SIMD3<Double>(repeating: 0),
        orientation: simd_quatd(angle: 0, axis: SIMD3<Double>(0, 0, 1)),
        angularVelocity: SIMD3<Double>(repeating: 0)
    )
    let hoverThrust = params.mass * params.gravity / 4.0
    let store = WorldStore(state: state, motorThrusts: try MotorThrusts.uniform(hoverThrust))
    let timeStep = try TimeStep(delta: 0.001)

    var sensor = try IMU6SensorField(
        parameters: params,
        mixer: mixer,
        store: store,
        timeStep: timeStep,
        noiseSeed: 42,
        gyroNoiseStdDev: 0,
        gyroBias: 0,
        gyroRandomWalkSigma: 0,
        accelNoiseStdDev: 0,
        accelBias: 0,
        accelRandomWalkSigma: 0,
        delaySteps: 0
    )

    let samples = try sensor.sample(time: try WorldTime(stepIndex: 1, time: timeStep.delta))
    #expect(samples.count == 6)

    let gyroZ = samples.first { $0.channelIndex == 2 }?.value ?? 0
    let accelZ = samples.first { $0.channelIndex == 5 }?.value ?? 0

    #expect(abs(gyroZ) < 1e-9)
    #expect(abs(accelZ - params.gravity) < 1e-6)
}
