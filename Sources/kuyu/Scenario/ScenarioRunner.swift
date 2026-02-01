import simd

public struct ScenarioRunner<Cut: CutInterface, Dal: ExternalDAL> {
    public var parameters: QuadrotorParameters
    public var mixer: QuadrotorMixer
    public var schedule: SimulationSchedule
    public var determinism: DeterminismConfig
    public var noise: IMU6NoiseConfig
    public var hoverThrustScale: Double

    public init(
        parameters: QuadrotorParameters = .baseline,
        mixer: QuadrotorMixer? = nil,
        schedule: SimulationSchedule,
        determinism: DeterminismConfig,
        noise: IMU6NoiseConfig = .zero,
        hoverThrustScale: Double = 1.0
    ) {
        self.parameters = parameters
        self.mixer = mixer ?? QuadrotorMixer(armLength: parameters.armLength, yawCoefficient: parameters.yawCoefficient)
        self.schedule = schedule
        self.determinism = determinism
        self.noise = noise
        self.hoverThrustScale = hoverThrustScale
    }

    public func runScenario(
        definition: ScenarioDefinition,
        cut: Cut,
        externalDal: Dal? = nil
    ) throws -> SimulationLog {
        let store = try buildStore(definition: definition)
        let timeStep = definition.config.timeStep

        let baseMaxThrusts = try MotorMaxThrusts.uniform(parameters.maxThrust)
        let actuatorBase = QuadrotorActuatorEngine(
            parameters: parameters,
            store: store,
            timeStep: timeStep,
            motorMaxThrusts: baseMaxThrusts
        )
        let actuator = ActuatorDegradationEngine(
            engine: actuatorBase,
            degradation: definition.actuatorDegradation
        )

        let disturbance = TorqueDisturbanceField(events: definition.torqueEvents, store: store)
        let plant = QuadrotorPlantEngine(
            parameters: parameters,
            mixer: mixer,
            store: store,
            timeStep: timeStep
        )

        let scaledNoise = try IMU6NoiseConfig(
            gyroNoiseStdDev: noise.gyroNoiseStdDev,
            gyroBias: noise.gyroBias,
            gyroRandomWalkSigma: noise.gyroRandomWalkSigma * definition.gyroDriftScale,
            accelNoiseStdDev: noise.accelNoiseStdDev,
            accelBias: noise.accelBias,
            accelRandomWalkSigma: noise.accelRandomWalkSigma,
            delaySteps: noise.delaySteps
        )

        let sensor = try IMU6SensorField(
            parameters: parameters,
            mixer: mixer,
            store: store,
            timeStep: timeStep,
            noiseSeed: definition.config.seed.rawValue,
            gyroNoiseStdDev: scaledNoise.gyroNoiseStdDev,
            gyroBias: scaledNoise.gyroBias,
            gyroRandomWalkSigma: scaledNoise.gyroRandomWalkSigma,
            accelNoiseStdDev: scaledNoise.accelNoiseStdDev,
            accelBias: scaledNoise.accelBias,
            accelRandomWalkSigma: scaledNoise.accelRandomWalkSigma,
            delaySteps: scaledNoise.delaySteps
        )

        let config = SimulationConfig(
            scenario: definition.config,
            schedule: schedule,
            determinism: determinism
        )

        var simulator = try WorldSimulator(
            config: config,
            disturbance: disturbance,
            actuator: actuator,
            plant: plant,
            sensor: sensor,
            cut: cut,
            externalDal: externalDal,
            store: store
        )

        return try simulator.run()
    }

    private func buildStore(definition: ScenarioDefinition) throws -> WorldStore {
        let orientation = definition.initialAttitude.toQuaternion()
        let angularVelocity = SIMD3<Double>(
            definition.initialAngularVelocity.x,
            definition.initialAngularVelocity.y,
            definition.initialAngularVelocity.z
        )

        let state = try QuadrotorState(
            position: SIMD3<Double>(repeating: 0),
            velocity: SIMD3<Double>(repeating: 0),
            orientation: orientation,
            angularVelocity: angularVelocity
        )

        let hoverThrust = parameters.mass * parameters.gravity / 4.0 * hoverThrustScale
        let thrusts = try MotorThrusts.uniform(hoverThrust)
        return WorldStore(state: state, motorThrusts: thrusts)
    }
}
