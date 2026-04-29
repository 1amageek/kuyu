import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

@MainActor
public struct KuyuSingleLiftTeacherDatasetRunner {
    public init() {}

    public func run(
        request: SimulationRunRequest,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        control: SimulationControl? = nil,
        telemetry: ((WorldStepLog) -> Void)? = nil
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

        let definitions = try KuyuSingleLiftTrainingSuite().scenarios()
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

        let result = SuiteRunResult(evaluations: evaluations, replayChecks: [], passed: evaluations.allSatisfy(\.passed))
        let aggregate = EvaluationAggregate.from(evaluations: result.evaluations)
        let summary = ValidationSummary(
            suitePassed: result.passed,
            evaluations: result.evaluations,
            replayChecks: result.replayChecks,
            manifest: ReferenceQuadrotorScenarioManifestBuilder().build(from: definitions),
            aggregate: aggregate
        )
        return KuyAtt1RunOutput(result: result, summary: summary, logs: logs)
    }
}
