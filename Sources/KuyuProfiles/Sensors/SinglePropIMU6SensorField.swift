import simd
import KuyuCore

public struct SinglePropIMU6SensorField: SensorField {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case negative(String)
    }

    public var parameters: ReferenceQuadrotorParameters
    public var store: ReferenceQuadrotorWorldStore
    public var timeStep: TimeStep
    public var environment: WorldEnvironment

    private var gyroNoise: [AxisNoiseModel]
    private var accelNoise: [AxisNoiseModel]
    private var delayBuffer: SampleDelayBuffer

    public init(
        parameters: ReferenceQuadrotorParameters,
        store: ReferenceQuadrotorWorldStore,
        timeStep: TimeStep,
        environment: WorldEnvironment = .standard,
        noiseSeed: UInt64,
        gyroNoiseStdDev: Double,
        gyroBias: Double,
        gyroRandomWalkSigma: Double,
        accelNoiseStdDev: Double,
        accelBias: Double,
        accelRandomWalkSigma: Double,
        delaySteps: UInt64 = 0
    ) throws {
        guard gyroNoiseStdDev.isFinite else { throw ValidationError.nonFinite("gyroNoiseStdDev") }
        guard gyroBias.isFinite else { throw ValidationError.nonFinite("gyroBias") }
        guard gyroRandomWalkSigma.isFinite else { throw ValidationError.nonFinite("gyroRandomWalkSigma") }
        guard accelNoiseStdDev.isFinite else { throw ValidationError.nonFinite("accelNoiseStdDev") }
        guard accelBias.isFinite else { throw ValidationError.nonFinite("accelBias") }
        guard accelRandomWalkSigma.isFinite else { throw ValidationError.nonFinite("accelRandomWalkSigma") }

        guard gyroNoiseStdDev >= 0 else { throw ValidationError.negative("gyroNoiseStdDev") }
        guard gyroRandomWalkSigma >= 0 else { throw ValidationError.negative("gyroRandomWalkSigma") }
        guard accelNoiseStdDev >= 0 else { throw ValidationError.negative("accelNoiseStdDev") }
        guard accelRandomWalkSigma >= 0 else { throw ValidationError.negative("accelRandomWalkSigma") }

        self.parameters = parameters
        self.store = store
        self.timeStep = timeStep
        self.environment = environment
        self.gyroNoise = [
            AxisNoiseModel(bias: gyroBias, noiseStdDev: gyroNoiseStdDev, randomWalkSigma: gyroRandomWalkSigma, seed: noiseSeed &+ 1),
            AxisNoiseModel(bias: gyroBias, noiseStdDev: gyroNoiseStdDev, randomWalkSigma: gyroRandomWalkSigma, seed: noiseSeed &+ 2),
            AxisNoiseModel(bias: gyroBias, noiseStdDev: gyroNoiseStdDev, randomWalkSigma: gyroRandomWalkSigma, seed: noiseSeed &+ 3)
        ]
        self.accelNoise = [
            AxisNoiseModel(bias: accelBias, noiseStdDev: accelNoiseStdDev, randomWalkSigma: accelRandomWalkSigma, seed: noiseSeed &+ 4),
            AxisNoiseModel(bias: accelBias, noiseStdDev: accelNoiseStdDev, randomWalkSigma: accelRandomWalkSigma, seed: noiseSeed &+ 5),
            AxisNoiseModel(bias: accelBias, noiseStdDev: accelNoiseStdDev, randomWalkSigma: accelRandomWalkSigma, seed: noiseSeed &+ 6)
        ]
        self.delayBuffer = SampleDelayBuffer(delaySteps: delaySteps)
    }

    public mutating func sample(time: WorldTime) throws -> [ChannelSample] {
        let thrust = store.motorThrusts.f1
        let forceZ = thrust + store.disturbances.forceWorld.z
        let specificForceZ = forceZ / parameters.mass

        let gyro = SIMD3<Double>(repeating: 0)
        let accel = SIMD3<Double>(0, 0, specificForceZ)

        let dt = timeStep.delta
        let gyroSamples = SIMD3<Double>(
            gyro.x + gyroNoise[0].sample(delta: dt),
            gyro.y + gyroNoise[1].sample(delta: dt),
            gyro.z + gyroNoise[2].sample(delta: dt)
        )
        let accelSamples = SIMD3<Double>(
            accel.x + accelNoise[0].sample(delta: dt),
            accel.y + accelNoise[1].sample(delta: dt),
            accel.z + accelNoise[2].sample(delta: dt)
        )

        let timestamp = time.time
        let altitudeZ = store.state.position.z
        let velocityZ = store.state.velocity.z
        let samples = [
            try ChannelSample(channelIndex: 0, value: gyroSamples.x, timestamp: timestamp),
            try ChannelSample(channelIndex: 1, value: gyroSamples.y, timestamp: timestamp),
            try ChannelSample(channelIndex: 2, value: gyroSamples.z, timestamp: timestamp),
            try ChannelSample(channelIndex: 3, value: accelSamples.x, timestamp: timestamp),
            try ChannelSample(channelIndex: 4, value: accelSamples.y, timestamp: timestamp),
            try ChannelSample(channelIndex: 5, value: accelSamples.z, timestamp: timestamp),
            try ChannelSample(channelIndex: 6, value: altitudeZ, timestamp: timestamp),
            try ChannelSample(channelIndex: 7, value: velocityZ, timestamp: timestamp)
        ]

        return delayBuffer.push(samples)
    }
}
