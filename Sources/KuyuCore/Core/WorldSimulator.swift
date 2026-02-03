import Foundation

public struct WorldSimulator<
    Disturbance: DisturbanceField,
    Actuator: ActuatorEngine,
    Plant: PlantEngine,
    Sensor: SensorField,
    Cut: CutInterface,
    Dal: ExternalDAL
> {
    public var config: SimulationConfig
    public var disturbance: Disturbance
    public var actuator: Actuator
    public var plant: Plant
    public var sensor: Sensor
    public var cut: Cut
    public var externalDal: Dal?
    public var store: WorldStore

    private var time: WorldTime

    public init(
        config: SimulationConfig,
        disturbance: Disturbance,
        actuator: Actuator,
        plant: Plant,
        sensor: Sensor,
        cut: Cut,
        externalDal: Dal? = nil,
        store: WorldStore
    ) throws {
        self.config = config
        self.disturbance = disturbance
        self.actuator = actuator
        self.plant = plant
        self.sensor = sensor
        self.cut = cut
        self.externalDal = externalDal
        self.store = store
        self.time = try WorldTime(stepIndex: 0, time: 0.0)
    }

    @MainActor
    public mutating func run(control: SimulationControl? = nil) async throws -> SimulationLog {
        let dt = config.scenario.timeStep.delta
        let steps = Int((config.scenario.duration / dt).rounded(.down))
        var logs: [WorldStepLog] = []
        logs.reserveCapacity(steps + 1)
        let configHash = try ConfigHash.hash(config)

        for _ in 0..<steps {
            if let control {
                try await control.checkpoint()
            }
            let log = try step(deltaTime: dt)
            logs.append(log)
        }

        return SimulationLog(
            scenarioId: config.scenario.id,
            seed: config.scenario.seed,
            timeStep: config.scenario.timeStep,
            determinism: config.determinism,
            configHash: configHash,
            events: logs
        )
    }

    public mutating func step(deltaTime: TimeInterval) throws -> WorldStepLog {
        time = try time.advanced(by: deltaTime)
        var events: [ExecutionEvent] = []

        events.append(.timeAdvance)

        try disturbance.update(time: time)
        events.append(.disturbanceUpdate)

        if config.schedule.actuator.isDue(stepIndex: time.stepIndex) {
            try actuator.update(time: time)
            events.append(.actuatorUpdate)
        }

        try plant.integrate(time: time)
        events.append(.plantIntegrate)

        var samples: [ChannelSample] = []
        if config.schedule.sensor.isDue(stepIndex: time.stepIndex) {
            samples = try sensor.sample(time: time)
            events.append(.sensorSample)
        }

        var output: CutOutput?
        var driveIntents: [DriveIntent] = []
        var reflexCorrections: [ReflexCorrection] = []
        if config.schedule.cut.isDue(stepIndex: time.stepIndex) {
            output = try cut.update(samples: samples, time: time)
            events.append(.cutUpdate)
        }

        var commands: [ActuatorCommand] = []
        if let output {
            switch output {
            case .actuatorCommands(let direct):
                commands = direct
            case .driveIntents(let drives, let corrections):
                driveIntents = drives
                reflexCorrections = corrections
                if config.schedule.externalDal?.isDue(stepIndex: time.stepIndex) == true, var dal = externalDal {
                    let telemetry = ExternalDALTelemetry(motorThrusts: store.motorThrusts)
                    commands = try dal.update(
                        drives: drives,
                        corrections: corrections,
                        telemetry: telemetry,
                        time: time
                    )
                    externalDal = dal
                    events.append(.externalDalUpdate)
                }
            }
        }

        if !commands.isEmpty {
            try actuator.apply(commands: commands, time: time)
            events.append(.applyCommands)
        }

        events.append(.logging)
        events.append(.replayCheck)

        let safetyTrace = SafetyTrace(state: store.state)
        let stateSnapshot = QuadrotorStateSnapshot(state: store.state)
        let disturbanceTorque = store.disturbances.torqueAxis3()
        let disturbanceForce = store.disturbances.forceAxis3()

        return WorldStepLog(
            time: time,
            events: events,
            sensorSamples: samples,
            driveIntents: driveIntents,
            reflexCorrections: reflexCorrections,
            actuatorCommands: commands,
            motorThrusts: store.motorThrusts,
            safetyTrace: safetyTrace,
            stateSnapshot: stateSnapshot,
            disturbanceTorqueBody: disturbanceTorque,
            disturbanceForceWorld: disturbanceForce
        )
    }
}
