public struct KuyAtt1Runner {
    public var parameters: QuadrotorParameters
    public var mixer: QuadrotorMixer
    public var schedule: SimulationSchedule
    public var determinism: DeterminismConfig
    public var noise: IMU6NoiseConfig
    public var gains: ImuRateDampingCutGains

    public init(
        parameters: QuadrotorParameters = .baseline,
        mixer: QuadrotorMixer? = nil,
        schedule: SimulationSchedule,
        determinism: DeterminismConfig,
        noise: IMU6NoiseConfig = .zero,
        gains: ImuRateDampingCutGains
    ) {
        self.parameters = parameters
        self.mixer = mixer ?? QuadrotorMixer(armLength: parameters.armLength, yawCoefficient: parameters.yawCoefficient)
        self.schedule = schedule
        self.determinism = determinism
        self.noise = noise
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

    public func run(referenceLogs: [ScenarioKey: SimulationLog] = [:]) throws -> SuiteRunResult {
        let runner = ScenarioRunner<ImuRateDampingCut, UnusedExternalDAL>(
            parameters: parameters,
            mixer: mixer,
            schedule: schedule,
            determinism: determinism,
            noise: noise,
            hoverThrustScale: gains.hoverThrustScale
        )

        let validation = KuyAtt1Validation(runner: runner)

        return try validation.run(
            cutFactory: { _ in
                let hoverThrust = parameters.mass * parameters.gravity / 4.0 * gains.hoverThrustScale
                return try ImuRateDampingCut(
                    hoverThrust: hoverThrust,
                    kp: gains.kp,
                    kd: gains.kd,
                    yawDamping: gains.yawDamping,
                    armLength: parameters.armLength,
                    yawCoefficient: parameters.yawCoefficient
                )
            },
            externalDalFactory: { _ in nil },
            referenceLogs: referenceLogs
        )
    }

    public func runWithLogs(referenceLogs: [ScenarioKey: SimulationLog] = [:]) throws -> KuyAtt1RunOutput {
        let runner = ScenarioRunner<ImuRateDampingCut, UnusedExternalDAL>(
            parameters: parameters,
            mixer: mixer,
            schedule: schedule,
            determinism: determinism,
            noise: noise,
            hoverThrustScale: gains.hoverThrustScale
        )

        let validation = KuyAtt1Validation(runner: runner)
        let output = try validation.runWithLogs(
            cutFactory: { _ in
                let hoverThrust = parameters.mass * parameters.gravity / 4.0 * gains.hoverThrustScale
                return try ImuRateDampingCut(
                    hoverThrust: hoverThrust,
                    kp: gains.kp,
                    kd: gains.kd,
                    yawDamping: gains.yawDamping,
                    armLength: parameters.armLength,
                    yawCoefficient: parameters.yawCoefficient
                )
            },
            externalDalFactory: { _ in nil },
            referenceLogs: referenceLogs
        )

        let summary = ValidationSummary(
            suitePassed: output.result.passed,
            evaluations: output.result.evaluations,
            replayChecks: output.result.replayChecks,
            manifest: output.manifest
        )

        return KuyAtt1RunOutput(result: output.result, summary: summary, logs: output.logs)
    }
}
