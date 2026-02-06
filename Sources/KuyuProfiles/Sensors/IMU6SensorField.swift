import simd
import KuyuCore

public struct IMU6SensorField: SensorField {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case negative(String)
    }

    public var parameters: ReferenceQuadrotorParameters
    public var mixer: ReferenceQuadrotorMixer
    public var store: ReferenceQuadrotorWorldStore
    public var timeStep: TimeStep
    public var environment: WorldEnvironment

    private var gyroNoise: [AxisNoiseModel]
    private var accelNoise: [AxisNoiseModel]
    private var delayBuffer: SampleDelayBuffer

    public init(
        parameters: ReferenceQuadrotorParameters,
        mixer: ReferenceQuadrotorMixer,
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
        self.mixer = mixer
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
        let mix = mixer.mix(thrusts: store.motorThrusts)
        var bodyForce = mix.forceBody
        var worldForce = store.disturbances.forceWorld
        let gravity = environment.effectiveGravity(defaultGravity: parameters.gravity)

        if environment.usage.useAtmosphere {
            let density = environment.airDensity()
            let ratio = density / WorldEnvironment.seaLevelDensity
            bodyForce *= ratio

            let windVelocity = environment.usage.useWind ? environment.windVelocityWorld.simd : SIMD3<Double>(repeating: 0)
            let airVelocity = store.state.velocity - windVelocity
            let speed = simd_length(airVelocity)
            let aero = parameters.aerodynamics

            if speed > 0, aero.dragCoefficient > 0, aero.referenceArea > 0 {
                let dragMagnitude = 0.5 * density * aero.dragCoefficient * aero.referenceArea * speed * speed
                let drag = -dragMagnitude * (airVelocity / speed)
                worldForce += drag
            }

            if aero.liftCoefficient > 0, aero.referenceArea > 0 {
                let airVelocityBody = store.state.orientation.inverse.act(airVelocity)
                let bodySpeed = simd_length(airVelocityBody)
                if bodySpeed > 0 {
                    let vHat = airVelocityBody / bodySpeed
                    let bodyUp = SIMD3<Double>(0, 0, 1)
                    let liftPlane = simd_cross(vHat, simd_cross(bodyUp, vHat))
                    let liftPlaneMag = simd_length(liftPlane)
                    if liftPlaneMag > 0 {
                        let liftMagnitude = 0.5 * density * aero.liftCoefficient * aero.referenceArea * bodySpeed * bodySpeed
                        let liftBody = liftPlane / liftPlaneMag * liftMagnitude
                        worldForce += store.state.orientation.act(liftBody)
                    }
                }
            }

            if aero.bodyVolume > 0 {
                let gravityWorld = SIMD3<Double>(0, 0, -gravity)
                let buoyancy = -gravityWorld * (density * aero.bodyVolume)
                worldForce += buoyancy
            }
        }

        let input = ReferenceQuadrotorInput(
            bodyForce: bodyForce,
            bodyTorque: mix.torqueBody + store.disturbances.torqueBody,
            worldForce: worldForce
        )

        let gyro = store.state.angularVelocity
        let accel = ReferenceQuadrotorDynamics.specificForceBody(
            state: store.state,
            input: input,
            parameters: parameters,
            gravity: gravity
        )

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
        let samples = [
            try ChannelSample(channelIndex: 0, value: gyroSamples.x, timestamp: timestamp),
            try ChannelSample(channelIndex: 1, value: gyroSamples.y, timestamp: timestamp),
            try ChannelSample(channelIndex: 2, value: gyroSamples.z, timestamp: timestamp),
            try ChannelSample(channelIndex: 3, value: accelSamples.x, timestamp: timestamp),
            try ChannelSample(channelIndex: 4, value: accelSamples.y, timestamp: timestamp),
            try ChannelSample(channelIndex: 5, value: accelSamples.z, timestamp: timestamp)
        ]

        return delayBuffer.push(samples)
    }
}
