import kuyu

struct SimulationRunnerService: Sendable {

    func run(request: SimulationRunRequest) throws -> KuyAtt1RunOutput {
        let schedule = try SimulationSchedule(
            sensor: SubsystemSchedule(periodSteps: 1),
            actuator: SubsystemSchedule(periodSteps: 1),
            cut: SubsystemSchedule(periodSteps: request.cutPeriodSteps),
            externalDal: SubsystemSchedule(periodSteps: request.cutPeriodSteps)
        )
        let parameters = loadParameters(request: request)
        let runner = ScenarioRunner<ImuRateDampingDriveCut, ManasLearningDAL>(
            parameters: parameters,
            schedule: schedule,
            determinism: request.determinism,
            noise: request.noise,
            hoverThrustScale: request.gains.hoverThrustScale
        )
        let validation = KuyAtt1Validation(runner: runner)
        let output = try validation.runWithLogs(
            cutFactory: { _ in
                let hoverThrust = parameters.mass * parameters.gravity / 4.0 * request.gains.hoverThrustScale
                return try ImuRateDampingDriveCut(
                    hoverThrust: hoverThrust,
                    kp: request.gains.kp,
                    kd: request.gains.kd,
                    yawDamping: request.gains.yawDamping,
                    armLength: parameters.armLength,
                    yawCoefficient: parameters.yawCoefficient
                )
            },
            externalDalFactory: { definition in
                let updatePeriod = definition.config.timeStep.delta * Double(request.cutPeriodSteps)
                return try ManasLearningDAL(
                    learningMode: request.learningMode,
                    parameters: parameters,
                    updatePeriod: updatePeriod
                )
            }
        )

        let summary = ValidationSummary(
            suitePassed: output.result.passed,
            evaluations: output.result.evaluations,
            replayChecks: output.result.replayChecks,
            manifest: output.manifest
        )

        return KuyAtt1RunOutput(result: output.result, summary: summary, logs: output.logs)
    }

    private func loadParameters(request: SimulationRunRequest) -> QuadrotorParameters {
        if let override = request.overrideParameters {
            return override
        }

        let descriptorPath = request.modelDescriptorPath
        let trimmed = descriptorPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .baseline
        }

        do {
            let loader = RobotModelLoader()
            let loaded = try loader.loadDescriptor(path: trimmed)
            return try loader.loadQuadrotorParameters(descriptor: loaded)
        } catch {
            return .baseline
        }
    }
}
