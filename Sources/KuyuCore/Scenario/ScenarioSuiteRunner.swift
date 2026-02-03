public struct ScenarioSuiteRunner<Cut: CutInterface, Dal: ExternalDAL> {
    public var runner: ScenarioRunner<Cut, Dal>
    public var evaluator: ScenarioEvaluator
    public var replayChecker: ReplayChecker

    public init(
        runner: ScenarioRunner<Cut, Dal>,
        evaluator: ScenarioEvaluator = ScenarioEvaluator(),
        replayChecker: ReplayChecker = ReplayChecker()
    ) {
        self.runner = runner
        self.evaluator = evaluator
        self.replayChecker = replayChecker
    }

    @MainActor
    public func run(
        definitions: [ScenarioDefinition],
        cutFactory: (ScenarioDefinition) throws -> Cut,
        externalDalFactory: ((ScenarioDefinition) throws -> Dal?)? = nil,
        referenceLogs: [ScenarioKey: SimulationLog] = [:],
        control: SimulationControl? = nil
    ) async throws -> SuiteRunResult {
        var evaluations: [ScenarioEvaluation] = []
        var replayChecks: [ReplayCheckResult] = []

        for definition in definitions {
            if let control {
                try await control.checkpoint()
            }
            let cut = try cutFactory(definition)
            let externalDal = try externalDalFactory?(definition) ?? nil
            let log = try await runner.runScenario(
                definition: definition,
                cut: cut,
                externalDal: externalDal,
                control: control
            )

            let evaluation = evaluator.evaluate(definition: definition, log: log)
            evaluations.append(evaluation)

            let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
            if let reference = referenceLogs[key] {
                let replay = try replayChecker.check(reference: reference, candidate: log)
                replayChecks.append(replay)
            }
        }

        let evaluationPass = evaluations.allSatisfy { $0.passed }
        let replayPass = replayChecks.allSatisfy { $0.passed }
        let passed = evaluationPass && replayPass

        return SuiteRunResult(
            evaluations: evaluations,
            replayChecks: replayChecks,
            passed: passed
        )
    }
}
