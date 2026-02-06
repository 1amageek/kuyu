import Foundation

public struct WorldSimulator<
    Disturbance: DisturbanceField,
    Actuator: ActuatorEngine,
    Plant: PlantEngine,
    Sensor: SensorField,
    Cut: CutInterface,
    Nerve: MotorNerveEndpoint
> {
    public var config: SimulationConfig
    public var disturbance: Disturbance
    public var actuator: Actuator
    public var plant: Plant
    public var sensor: Sensor
    public var cut: Cut
    public var motorNerve: Nerve?

    private var time: WorldTime

    public init(
        config: SimulationConfig,
        disturbance: Disturbance,
        actuator: Actuator,
        plant: Plant,
        sensor: Sensor,
        cut: Cut,
        motorNerve: Nerve? = nil
    ) throws {
        self.config = config
        self.disturbance = disturbance
        self.actuator = actuator
        self.plant = plant
        self.sensor = sensor
        self.cut = cut
        self.motorNerve = motorNerve
        self.time = try WorldTime(stepIndex: 0, time: 0.0)
    }

    @MainActor
    public mutating func run(
        control: SimulationControl? = nil,
        telemetry: ((WorldStepLog) -> Void)? = nil,
        failureCheck: ((WorldStepLog) -> FailureEvent?)? = nil
    ) async throws -> SimulationLog {
        let dt = config.scenario.timeStep.delta
        let steps = Int((config.scenario.duration / dt).rounded(.down))
        var logs: [WorldStepLog] = []
        logs.reserveCapacity(steps + 1)
        let configHash = try ConfigHash.hash(config)
        var failureEvent: FailureEvent?

        for _ in 0..<steps {
            if let control {
                try await control.checkpoint()
            }
            let log = try step(deltaTime: dt)
            telemetry?(log)
            logs.append(log)
            if failureEvent == nil, let failureCheck, let event = failureCheck(log) {
                failureEvent = event
                break
            }
            if (log.time.stepIndex % 20) == 0 {
                await Task.yield()
            }
        }

        return SimulationLog(
            scenarioId: config.scenario.id,
            seed: config.scenario.seed,
            timeStep: config.scenario.timeStep,
            determinism: config.determinism,
            configHash: configHash,
            events: logs,
            failureReason: failureEvent?.reason,
            failureTime: failureEvent?.time
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
        var motorNerveTrace: MotorNerveTrace?
        if config.schedule.cut.isDue(stepIndex: time.stepIndex) {
            output = try cut.update(samples: samples, time: time)
            events.append(.cutUpdate)
        }

        var values: [ActuatorValue] = []
        if let output {
            switch output {
            case .actuatorValues(let direct):
                values = direct
            case .driveIntents(let drives, let corrections):
                driveIntents = drives
                reflexCorrections = corrections
                if config.schedule.motorNerve?.isDue(stepIndex: time.stepIndex) == true, var nerve = motorNerve {
                    let telemetry = MotorNerveTelemetry(actuatorTelemetry: actuator.telemetrySnapshot())
                    values = try nerve.update(
                        input: drives,
                        corrections: corrections,
                        telemetry: telemetry,
                        time: time
                    )
                    if let traceProvider = nerve as? MotorNerveTraceProvider {
                        motorNerveTrace = traceProvider.lastTrace
                    }
                    motorNerve = nerve
                    events.append(.motorNerveUpdate)
                }
            }
        }

        if !values.isEmpty {
            try actuator.apply(values: values, time: time)
            events.append(.applyCommands)
        }

        events.append(.logging)
        events.append(.replayCheck)

        let safetyTrace = plant.safetyTrace()
        let plantState = plant.snapshot()
        let disturbanceSnapshot = disturbance.snapshot()

        return WorldStepLog(
            time: time,
            events: events,
            sensorSamples: samples,
            driveIntents: driveIntents,
            reflexCorrections: reflexCorrections,
            actuatorValues: values,
            actuatorTelemetry: actuator.telemetrySnapshot(),
            motorNerveTrace: motorNerveTrace,
            safetyTrace: safetyTrace,
            plantState: plantState,
            disturbances: disturbanceSnapshot
        )
    }
}
