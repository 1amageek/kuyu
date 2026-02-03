import simd

public struct ScenarioRunner<Cut: CutInterface, Dal: ExternalDAL> {
    public var parameters: QuadrotorParameters
    public var mixer: QuadrotorMixer
    public var schedule: SimulationSchedule
    public var determinism: DeterminismConfig
    public var noise: IMU6NoiseConfig
    public var environment: WorldEnvironment
    public var hoverThrustScale: Double

    public init(
        parameters: QuadrotorParameters = .baseline,
        mixer: QuadrotorMixer? = nil,
        schedule: SimulationSchedule,
        determinism: DeterminismConfig,
        noise: IMU6NoiseConfig = .zero,
        environment: WorldEnvironment = .standard,
        hoverThrustScale: Double = 1.0
    ) {
        self.parameters = parameters
        self.mixer = mixer ?? QuadrotorMixer(armLength: parameters.armLength, yawCoefficient: parameters.yawCoefficient)
        self.schedule = schedule
        self.determinism = determinism
        self.noise = noise
        self.environment = environment
        self.hoverThrustScale = hoverThrustScale
    }

    @MainActor
    public func runScenario(
        definition: ScenarioDefinition,
        cut: Cut,
        externalDal: Dal? = nil,
        control: SimulationControl? = nil
    ) async throws -> SimulationLog {
        let store = try buildStore(definition: definition)
        let timeStep = definition.config.timeStep

        let baseMaxThrusts = try MotorMaxThrusts.uniform(parameters.maxThrust)
        let actuatorBase = QuadrotorActuatorEngine(
            parameters: parameters,
            store: store,
            timeStep: timeStep,
            motorMaxThrusts: baseMaxThrusts
        )
        let degraded = ActuatorDegradationEngine(
            engine: actuatorBase,
            degradation: definition.actuatorDegradation
        )
        let actuator = SwappableActuatorEngine(
            engine: degraded,
            baseMaxThrusts: baseMaxThrusts,
            swapEvents: definition.swapEvents,
            hfEvents: definition.hfEvents
        )

        let disturbance = TorqueDisturbanceField(
            events: definition.torqueEvents,
            hfEvents: definition.hfEvents,
            store: store
        )
        let plant = QuadrotorPlantEngine(
            parameters: parameters,
            mixer: mixer,
            store: store,
            timeStep: timeStep,
            environment: environment
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

        let baseSensor = try IMU6SensorField(
            parameters: parameters,
            mixer: mixer,
            store: store,
            timeStep: timeStep,
            environment: environment,
            noiseSeed: definition.config.seed.rawValue,
            gyroNoiseStdDev: scaledNoise.gyroNoiseStdDev,
            gyroBias: scaledNoise.gyroBias,
            gyroRandomWalkSigma: scaledNoise.gyroRandomWalkSigma,
            accelNoiseStdDev: scaledNoise.accelNoiseStdDev,
            accelBias: scaledNoise.accelBias,
            accelRandomWalkSigma: scaledNoise.accelRandomWalkSigma,
            delaySteps: scaledNoise.delaySteps
        )
        let sensor = SwappableSensorField(
            base: baseSensor,
            swapEvents: definition.swapEvents,
            hfEvents: definition.hfEvents,
            baseNoise: scaledNoise,
            seed: definition.config.seed.rawValue
        )

        let config = SimulationConfig(
            scenario: definition.config,
            schedule: schedule,
            determinism: determinism,
            environment: environment
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

        return try await simulator.run(control: control)
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
