public struct KuyAtt1Validation<Cut: CutInterface, Dal: ExternalDAL> {
    public var suite: KuyAtt1Suite
    public var runner: ScenarioRunner<Cut, Dal>
    public var suiteRunner: ScenarioSuiteRunner<Cut, Dal>

    public init(runner: ScenarioRunner<Cut, Dal>) {
        self.suite = KuyAtt1Suite()
        self.runner = runner
        self.suiteRunner = ScenarioSuiteRunner(runner: runner)
    }

    public func run(
        cutFactory: (ScenarioDefinition) throws -> Cut,
        externalDalFactory: ((ScenarioDefinition) throws -> Dal?)? = nil,
        referenceLogs: [ScenarioKey: SimulationLog] = [:]
    ) throws -> SuiteRunResult {
        let definitions = try suite.scenarios()
        return try suiteRunner.run(
            definitions: definitions,
            cutFactory: cutFactory,
            externalDalFactory: externalDalFactory,
            referenceLogs: referenceLogs
        )
    }

    public func runWithLogs(
        cutFactory: (ScenarioDefinition) throws -> Cut,
        externalDalFactory: ((ScenarioDefinition) throws -> Dal?)? = nil,
        referenceLogs: [ScenarioKey: SimulationLog] = [:]
    ) throws -> (result: SuiteRunResult, logs: [ScenarioLogEntry], manifest: [ScenarioManifest]) {
        let definitions = try suite.scenarios()
        let manifest = ScenarioManifestBuilder().build(from: definitions)

        var evaluations: [ScenarioEvaluation] = []
        var replayChecks: [ReplayCheckResult] = []
        var logs: [ScenarioLogEntry] = []

        for definition in definitions {
            let cut = try cutFactory(definition)
            let externalDal = try externalDalFactory?(definition) ?? nil
            let log = try runner.runScenario(definition: definition, cut: cut, externalDal: externalDal)
            let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
            logs.append(ScenarioLogEntry(key: key, log: log))

            let evaluation = ScenarioEvaluator().evaluate(definition: definition, log: log)
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
