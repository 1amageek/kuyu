import KuyuCore

public struct KuyAtt1Validation<Cut: CutInterface, Nerve: MotorNerveEndpoint> {
    public var suite: KuyAtt1Suite
    public var runner: ReferenceQuadrotorScenarioRunner<Cut, Nerve>
    public var suiteRunner: ReferenceQuadrotorScenarioSuiteRunner<Cut, Nerve>

    public init(runner: ReferenceQuadrotorScenarioRunner<Cut, Nerve>) {
        self.suite = KuyAtt1Suite()
        self.runner = runner
        self.suiteRunner = ReferenceQuadrotorScenarioSuiteRunner(runner: runner, evaluator: ReferenceQuadrotorScenarioEvaluator())
    }

    @MainActor
    public func run(
        cutFactory: (ReferenceQuadrotorScenarioDefinition) throws -> Cut,
        motorNerveFactory: ((ReferenceQuadrotorScenarioDefinition) throws -> Nerve?)? = nil,
        referenceLogs: [ScenarioKey: SimulationLog] = [:],
        control: SimulationControl? = nil,
        telemetry: ((WorldStepLog) -> Void)? = nil
    ) async throws -> SuiteRunResult {
        let definitions = try suite.scenarios()
        return try await suiteRunner.run(
            definitions: definitions,
            cutFactory: cutFactory,
            motorNerveFactory: motorNerveFactory,
            referenceLogs: referenceLogs,
            control: control,
            telemetry: telemetry
        )
    }

    @MainActor
    public func runWithLogs(
        cutFactory: (ReferenceQuadrotorScenarioDefinition) throws -> Cut,
        motorNerveFactory: ((ReferenceQuadrotorScenarioDefinition) throws -> Nerve?)? = nil,
        referenceLogs: [ScenarioKey: SimulationLog] = [:],
        control: SimulationControl? = nil,
        telemetry: ((WorldStepLog) -> Void)? = nil
    ) async throws -> (result: SuiteRunResult, logs: [ScenarioLogEntry], manifest: [ReferenceQuadrotorScenarioManifest]) {
        let definitions = try suite.scenarios()
        let manifest = ReferenceQuadrotorScenarioManifestBuilder().build(from: definitions)

        var evaluations: [ScenarioEvaluation] = []
        var replayChecks: [ReplayCheckResult] = []
        var logs: [ScenarioLogEntry] = []

        for definition in definitions {
            if let control {
                try await control.checkpoint()
            }
            let cut = try cutFactory(definition)
            let motorNerve = try motorNerveFactory?(definition) ?? nil
            let log = try await runner.runScenario(
                definition: definition,
                cut: cut,
                motorNerve: motorNerve,
                control: control,
                telemetry: telemetry
            )
            let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
            logs.append(ScenarioLogEntry(key: key, log: log))

            let evaluation = ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log)
            evaluations.append(evaluation)

            if let reference = referenceLogs[key] {
                let replay = try ReplayChecker().check(reference: reference, candidate: log)
                replayChecks.append(replay)
            }
        }

        let evaluationPass = evaluations.allSatisfy { $0.passed }
        let replayPass = replayChecks.allSatisfy { $0.passed }
        let result = SuiteRunResult(evaluations: evaluations, replayChecks: replayChecks, passed: evaluationPass && replayPass)
        return (result, logs, manifest)
    }
}
