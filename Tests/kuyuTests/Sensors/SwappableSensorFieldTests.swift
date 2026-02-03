import simd
import Testing
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func swappableSensorAppliesBiasShift() async throws {
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
    let baseNoise = try IMU6NoiseConfig(
        gyroNoiseStdDev: 0,
        gyroBias: 0,
        gyroRandomWalkSigma: 0,
        accelNoiseStdDev: 0,
        accelBias: 0,
        accelRandomWalkSigma: 0,
        delaySteps: 0
    )

    let baseSensor = try IMU6SensorField(
        parameters: params,
        mixer: mixer,
        store: store,
        timeStep: timeStep,
        noiseSeed: 42,
        gyroNoiseStdDev: baseNoise.gyroNoiseStdDev,
        gyroBias: baseNoise.gyroBias,
        gyroRandomWalkSigma: baseNoise.gyroRandomWalkSigma,
        accelNoiseStdDev: baseNoise.accelNoiseStdDev,
        accelBias: baseNoise.accelBias,
        accelRandomWalkSigma: baseNoise.accelRandomWalkSigma,
        delaySteps: baseNoise.delaySteps
    )

    let swap = try SensorSwapEvent(
        kind: .calibShift,
        startTime: 0.0,
        duration: 1.0,
        targetChannels: [0],
        gainScale: 1.0,
        biasShift: 1.0,
        noiseScale: 1.0,
        dropoutProbability: 0.0,
        delayShiftSteps: 0
    )

    var sensor = SwappableSensorField(
        base: baseSensor,
        swapEvents: [.sensor(swap)],
        hfEvents: [],
        baseNoise: baseNoise,
        seed: 99
    )

    let samples = try sensor.sample(time: try WorldTime(stepIndex: 1, time: timeStep.delta))
    let gyroX = samples.first { $0.channelIndex == 0 }?.value ?? 0
    #expect(abs(gyroX - 1.0) < 1e-6)
}
