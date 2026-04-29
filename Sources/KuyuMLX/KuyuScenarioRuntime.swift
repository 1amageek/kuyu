import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

@MainActor
public struct KuyuScenarioRuntime {
    public let modelStore: ManasMLXModelStore

    public init(modelStore: ManasMLXModelStore) {
        self.modelStore = modelStore
    }

    public func run(
        request: SimulationRunRequest,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        descriptor: RobotDescriptor?,
        control: SimulationControl? = nil,
        telemetry: ((WorldStepLog) -> Void)? = nil
    ) async throws -> KuyAtt1RunOutput {
        switch request.controller {
        case .baseline, .teacherBaseline, .sensorBaseline:
            return try await runBaseline(
                request: request,
                parameters: parameters,
                schedule: schedule,
                control: control,
                telemetry: telemetry
            )
        case .manasMLX:
            try MLXRuntimePreflight().check()
            return try await modelStore.runManasMLX(
                parameters: parameters,
                schedule: schedule,
                request: request,
                descriptor: descriptor,
                control: control,
                telemetry: telemetry
            )
        }
    }

    private func runBaseline(
        request: SimulationRunRequest,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        control: SimulationControl?,
        telemetry: ((WorldStepLog) -> Void)?
    ) async throws -> KuyAtt1RunOutput {
        switch request.taskMode {
        case .attitude:
            let runner = KuyAtt1Runner(
                parameters: parameters,
                schedule: schedule,
                determinism: request.determinism,
                noise: request.noise,
                gains: request.gains,
                baselineMode: request.controller.kuyAtt1BaselineMode ?? .teacher
            )
            return try await runner.runWithLogs(control: control)
        case .lift:
            return try await runLiftBaseline(
                request: request,
                parameters: parameters,
                schedule: schedule,
                control: control,
                telemetry: telemetry
            )
        case .singleLift:
            return try await runSingleLiftBaseline(
                request: request,
                parameters: parameters,
                schedule: schedule,
                control: control,
                telemetry: telemetry
            )
        }
    }

    private func runLiftBaseline(
        request: SimulationRunRequest,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        control: SimulationControl?,
        telemetry: ((WorldStepLog) -> Void)?
    ) async throws -> KuyAtt1RunOutput {
        let runner = ReferenceQuadrotorScenarioRunner<ImuRateDampingDriveCut, LiftMotorNerve>(
            parameters: parameters,
            schedule: schedule,
            determinism: request.determinism,
            noise: request.noise,
            environment: .standard,
            hoverThrustScale: request.gains.hoverThrustScale
        )

        let definitions = try KuyLiftSuite().scenarios()
        var evaluations: [ScenarioEvaluation] = []
        var logs: [ScenarioLogEntry] = []

        for definition in definitions {
            if let control {
                try await control.checkpoint()
            }
            let cut = try ImuRateDampingDriveCut(
                hoverThrust: parameters.mass * parameters.gravity / 4.0 * request.gains.hoverThrustScale,
                kp: request.gains.kp,
                kd: request.gains.kd,
                yawDamping: request.gains.yawDamping,
                armLength: parameters.armLength,
                yawCoefficient: parameters.yawCoefficient,
                maxThrust: parameters.maxThrust,
                initialRoll: definition.initialAttitude.roll,
                initialPitch: definition.initialAttitude.pitch,
                tiltCorrectionTimeConstant: nil
            )
            let maxThrusts = try MotorMaxThrusts.uniform(parameters.maxThrust)
            let log = try await runner.runScenario(
                definition: definition,
                cut: cut,
                motorNerve: LiftMotorNerve(motorMaxThrusts: maxThrusts),
                control: control,
                telemetry: telemetry
            )
            let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
            logs.append(ScenarioLogEntry(key: key, log: log))
            evaluations.append(ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log))
        }

        return Self.makeOutput(definitions: definitions, evaluations: evaluations, replayChecks: [], logs: logs)
    }

    private func runSingleLiftBaseline(
        request: SimulationRunRequest,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        control: SimulationControl?,
        telemetry: ((WorldStepLog) -> Void)?
    ) async throws -> KuyAtt1RunOutput {
        let tunedParameters = try KuyuSingleLiftParameterTuning.tuned(
            parameters: parameters,
            hoverThrustScale: request.gains.hoverThrustScale
        )
        let runner = ReferenceQuadrotorScenarioRunner<SinglePropHoverCut, FixedSinglePropMotorNerve>(
            parameters: tunedParameters,
            schedule: schedule,
            determinism: request.determinism,
            noise: request.noise,
            environment: .standard,
            hoverThrustScale: request.gains.hoverThrustScale
        )

        let definitions = try KuySingleLiftSuite().scenarios()
        var evaluations: [ScenarioEvaluation] = []
        var logs: [ScenarioLogEntry] = []

        for definition in definitions {
            if let control {
                try await control.checkpoint()
            }
            let targetZ = definition.liftEnvelope?.targetZ ?? 0.5
            let cut = try SinglePropHoverCut(
                targetZ: targetZ,
                hoverThrust: tunedParameters.mass * tunedParameters.gravity * request.gains.hoverThrustScale,
                maxThrust: tunedParameters.maxThrust
            )
            let motorNerveConfig = FixedSinglePropMotorNerve.Config(
                maxThrust: tunedParameters.maxThrust,
                rateLimitPerSecond: 100.0,
                smoothingTimeConstant: nil,
                baseThrottle: 0.0
            )
            let log = try await runner.runScenario(
                definition: definition,
                cut: cut,
                motorNerve: FixedSinglePropMotorNerve(config: motorNerveConfig),
                control: control,
                telemetry: telemetry
            )
            let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
            logs.append(ScenarioLogEntry(key: key, log: log))
            evaluations.append(ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log))
        }

        return Self.makeOutput(definitions: definitions, evaluations: evaluations, replayChecks: [], logs: logs)
    }

    private nonisolated static func makeOutput(
        definitions: [ReferenceQuadrotorScenarioDefinition],
        evaluations: [ScenarioEvaluation],
        replayChecks: [ReplayCheckResult],
        logs: [ScenarioLogEntry]
    ) -> KuyAtt1RunOutput {
        let manifest = ReferenceQuadrotorScenarioManifestBuilder().build(from: definitions)
        let result = SuiteRunResult(
            evaluations: evaluations,
            replayChecks: replayChecks,
            passed: evaluations.allSatisfy { $0.passed }
        )
        let aggregate = EvaluationAggregate.from(evaluations: result.evaluations)
        let summary = ValidationSummary(
            suitePassed: result.passed,
            evaluations: result.evaluations,
            replayChecks: result.replayChecks,
            manifest: manifest,
            aggregate: aggregate
        )
        return KuyAtt1RunOutput(result: result, summary: summary, logs: logs)
    }
}
