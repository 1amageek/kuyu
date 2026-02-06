import KuyuCore

public struct PlantScenarioSuiteRunner<Runner: PlantScenarioRunner, Evaluator: ScenarioEvaluating> where Runner.Scenario == Evaluator.Scenario {
    public var runner: Runner
    public var evaluator: Evaluator
    public var replayChecker: ReplayChecker

    public init(
        runner: Runner,
        evaluator: Evaluator,
        replayChecker: ReplayChecker = ReplayChecker()
    ) {
        self.runner = runner
        self.evaluator = evaluator
        self.replayChecker = replayChecker
    }

    @MainActor
    public func run(
        definitions: [Runner.Scenario],
        cutFactory: (Runner.Scenario) throws -> Runner.Cut,
        motorNerveFactory: ((Runner.Scenario) throws -> Runner.Nerve?)? = nil,
        referenceLogs: [ScenarioKey: SimulationLog] = [:],
        control: SimulationControl? = nil,
        telemetry: ((WorldStepLog) -> Void)? = nil
    ) async throws -> SuiteRunResult {
        var evaluations: [ScenarioEvaluation] = []
        var replayChecks: [ReplayCheckResult] = []

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

            let evaluation = evaluator.evaluate(definition: definition, log: log)
            evaluations.append(evaluation)

            let key = ScenarioKey(scenarioId: log.scenarioId, seed: log.seed)
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
