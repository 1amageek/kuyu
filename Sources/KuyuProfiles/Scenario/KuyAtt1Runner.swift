import KuyuCore

public struct KuyAtt1Runner {
    public var parameters: ReferenceQuadrotorParameters
    public var mixer: ReferenceQuadrotorMixer
    public var schedule: SimulationSchedule
    public var determinism: DeterminismConfig
    public var noise: IMU6NoiseConfig
    public var environment: WorldEnvironment
    public var gains: ImuRateDampingCutGains

    public init(
        parameters: ReferenceQuadrotorParameters = .baseline,
        mixer: ReferenceQuadrotorMixer? = nil,
        schedule: SimulationSchedule,
        determinism: DeterminismConfig,
        noise: IMU6NoiseConfig = .zero,
        environment: WorldEnvironment = .standard,
        gains: ImuRateDampingCutGains
    ) {
        self.parameters = parameters
        self.mixer = mixer ?? ReferenceQuadrotorMixer(armLength: parameters.armLength, yawCoefficient: parameters.yawCoefficient)
        self.schedule = schedule
        self.determinism = determinism
        self.noise = noise
        self.environment = environment
        self.gains = gains
    }

    public static func baseline(
        gains: ImuRateDampingCutGains,
        noise: IMU6NoiseConfig = .zero,
        cutPeriodSteps: UInt64 = 2
    ) throws -> KuyAtt1Runner {
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        return KuyAtt1Runner(
            schedule: schedule,
            determinism: .tier1Baseline,
            noise: noise,
            gains: gains
        )
    }

    @MainActor
    public func run(
        referenceLogs: [ScenarioKey: SimulationLog] = [:],
        control: SimulationControl? = nil
    ) async throws -> SuiteRunResult {
        let runner = ReferenceQuadrotorScenarioRunner<ImuRateDampingDriveCut, FixedQuadMotorNerve>(
            parameters: parameters,
            mixer: mixer,
            schedule: schedule,
            determinism: determinism,
            noise: noise,
            environment: environment,
            hoverThrustScale: gains.hoverThrustScale
        )

        let validation = KuyAtt1Validation(runner: runner)

        return try await validation.run(
            cutFactory: { _ in
                let hoverThrust = parameters.mass * parameters.gravity / 4.0 * gains.hoverThrustScale
                return try ImuRateDampingDriveCut(
                    hoverThrust: hoverThrust,
                    kp: gains.kp,
                    kd: gains.kd,
                    yawDamping: gains.yawDamping,
                    armLength: parameters.armLength,
                    yawCoefficient: parameters.yawCoefficient,
                    maxThrust: parameters.maxThrust
                )
            },
            motorNerveFactory: { _ in
                let maxThrusts = try MotorMaxThrusts.uniform(parameters.maxThrust)
                let config = FixedQuadMotorNerve.Config(mixer: mixer, motorMaxThrusts: maxThrusts)
                return FixedQuadMotorNerve(config: config)
            },
            referenceLogs: referenceLogs,
            control: control
        )
    }

    @MainActor
    public func runWithLogs(
        referenceLogs: [ScenarioKey: SimulationLog] = [:],
        control: SimulationControl? = nil
    ) async throws -> KuyAtt1RunOutput {
        let runner = ReferenceQuadrotorScenarioRunner<ImuRateDampingDriveCut, FixedQuadMotorNerve>(
            parameters: parameters,
            mixer: mixer,
            schedule: schedule,
            determinism: determinism,
            noise: noise,
            environment: environment,
            hoverThrustScale: gains.hoverThrustScale
        )

        let validation = KuyAtt1Validation(runner: runner)
        let output = try await validation.runWithLogs(
            cutFactory: { _ in
                let hoverThrust = parameters.mass * parameters.gravity / 4.0 * gains.hoverThrustScale
                return try ImuRateDampingDriveCut(
                    hoverThrust: hoverThrust,
                    kp: gains.kp,
                    kd: gains.kd,
                    yawDamping: gains.yawDamping,
                    armLength: parameters.armLength,
                    yawCoefficient: parameters.yawCoefficient,
                    maxThrust: parameters.maxThrust
                )
            },
            motorNerveFactory: { _ in
                let maxThrusts = try MotorMaxThrusts.uniform(parameters.maxThrust)
                let config = FixedQuadMotorNerve.Config(mixer: mixer, motorMaxThrusts: maxThrusts)
                return FixedQuadMotorNerve(config: config)
            },
            referenceLogs: referenceLogs,
            control: control
        )

        let aggregate = EvaluationAggregate.from(evaluations: output.result.evaluations)
        let summary = ValidationSummary(
            suitePassed: output.result.passed,
            evaluations: output.result.evaluations,
            replayChecks: output.result.replayChecks,
            manifest: output.manifest,
            aggregate: aggregate
        )

        return KuyAtt1RunOutput(result: output.result, summary: summary, logs: output.logs)
    }
}
