import simd
import KuyuCore

/// Reference plant profile (quadrotor). Other morphologies should implement `PlantScenarioRunner`.
public struct ReferenceQuadrotorScenarioRunner<Cut: CutInterface, Nerve: MotorNerveEndpoint>: PlantScenarioRunner {
    public var parameters: ReferenceQuadrotorParameters
    public var mixer: ReferenceQuadrotorMixer
    public var schedule: SimulationSchedule
    public var determinism: DeterminismConfig
    public var noise: IMU6NoiseConfig
    public var environment: WorldEnvironment
    public var hoverThrustScale: Double

    public init(
        parameters: ReferenceQuadrotorParameters = .baseline,
        mixer: ReferenceQuadrotorMixer? = nil,
        schedule: SimulationSchedule,
        determinism: DeterminismConfig,
        noise: IMU6NoiseConfig = .zero,
        environment: WorldEnvironment = .standard,
        hoverThrustScale: Double = 1.0
    ) {
        self.parameters = parameters
        self.mixer = mixer ?? ReferenceQuadrotorMixer(armLength: parameters.armLength, yawCoefficient: parameters.yawCoefficient)
        self.schedule = schedule
        self.determinism = determinism
        self.noise = noise
        self.environment = environment
        self.hoverThrustScale = hoverThrustScale
    }

    @MainActor
    public func runScenario(
        definition: ReferenceQuadrotorScenarioDefinition,
        cut: Cut,
        motorNerve: Nerve? = nil,
        control: SimulationControl? = nil,
        telemetry: ((WorldStepLog) -> Void)? = nil
    ) async throws -> SimulationLog {
        let isSingleLift = definition.kind == .singleLiftHover
        let store = try buildStore(definition: definition)
        let timeStep = definition.config.timeStep

        let scaledNoise = try IMU6NoiseConfig(
            gyroNoiseStdDev: noise.gyroNoiseStdDev,
            gyroBias: noise.gyroBias,
            gyroRandomWalkSigma: noise.gyroRandomWalkSigma * definition.gyroDriftScale,
            accelNoiseStdDev: noise.accelNoiseStdDev,
            accelBias: noise.accelBias,
            accelRandomWalkSigma: noise.accelRandomWalkSigma,
            delaySteps: noise.delaySteps
        )

        if isSingleLift {
            let actuator = SinglePropActuatorEngine(
                maxThrust: parameters.maxThrust,
                motorTimeConstant: parameters.motorTimeConstant,
                store: store,
                timeStep: timeStep
            )
            let disturbance = TorqueDisturbanceField(
                events: [],
                hfEvents: [],
                store: store
            )
            let plant = SinglePropPlantEngine(
                parameters: parameters,
                store: store,
                timeStep: timeStep,
                environment: environment
            )
            let sensor = try SinglePropIMU6SensorField(
                parameters: parameters,
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
                motorNerve: motorNerve
            )

            var monitor = SafetyFailurePolicy(
                envelope: definition.safetyEnvelope,
                timeStep: definition.config.timeStep.delta
            )

            return try await simulator.run(
                control: control,
                telemetry: telemetry,
                failureCheck: { log in
                    monitor.update(log: log)
                }
            )
        }

        let baseMaxThrusts = try MotorMaxThrusts.uniform(parameters.maxThrust)
        let actuatorBase = ReferenceQuadrotorActuatorEngine(
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
        let plant = ReferenceQuadrotorPlantEngine(
            parameters: parameters,
            mixer: mixer,
            store: store,
            timeStep: timeStep,
            environment: environment
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
            motorNerve: motorNerve
        )

        var monitor = SafetyFailurePolicy(
            envelope: definition.safetyEnvelope,
            timeStep: definition.config.timeStep.delta
        )

        return try await simulator.run(
            control: control,
            telemetry: telemetry,
            failureCheck: { log in
                monitor.update(log: log)
            }
        )
    }

    private func buildStore(definition: ReferenceQuadrotorScenarioDefinition) throws -> ReferenceQuadrotorWorldStore {
        let isSingleLift = definition.kind == .singleLiftHover
        let orientation = isSingleLift
            ? simd_quatd(angle: 0.0, axis: SIMD3<Double>(0, 0, 1))
            : definition.initialAttitude.toQuaternion()
        let angularVelocity = SIMD3<Double>(
            definition.initialAngularVelocity.x,
            definition.initialAngularVelocity.y,
            definition.initialAngularVelocity.z
        )
        let initialPosition = SIMD3<Double>(
            definition.initialPosition.x,
            definition.initialPosition.y,
            definition.initialPosition.z
        )

        let state = try ReferenceQuadrotorState(
            position: initialPosition,
            velocity: SIMD3<Double>(repeating: 0),
            orientation: orientation,
            angularVelocity: isSingleLift ? SIMD3<Double>(repeating: 0) : angularVelocity
        )

        if isSingleLift {
            let hoverThrust = parameters.mass * parameters.gravity * hoverThrustScale
            let thrusts = try MotorThrusts(f1: hoverThrust, f2: 0, f3: 0, f4: 0)
            return ReferenceQuadrotorWorldStore(state: state, motorThrusts: thrusts)
        }

        let hoverThrust = parameters.mass * parameters.gravity / 4.0 * hoverThrustScale
        let thrusts = try MotorThrusts.uniform(hoverThrust)
        return ReferenceQuadrotorWorldStore(state: state, motorThrusts: thrusts)
    }

}
