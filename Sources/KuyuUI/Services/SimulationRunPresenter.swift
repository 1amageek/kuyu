import KuyuCore
import KuyuScenarios

struct SimulationRunPresenter {
    func record(output: KuyAtt1RunOutput) -> RunRecord {
        let evaluationsByKey = Dictionary(
            uniqueKeysWithValues: output.result.evaluations.map {
                (ScenarioKey(scenarioId: $0.scenarioId, seed: $0.seed), $0)
            }
        )

        let scenarios = output.logs.compactMap { entry -> ScenarioRunRecord? in
            guard let evaluation = evaluationsByKey[entry.key] else { return nil }
            return ScenarioRunRecord(
                id: entry.key,
                evaluation: evaluation,
                log: entry.log,
                metrics: ScenarioMetricsBuilder.build(log: entry.log)
            )
        }.sorted { lhs, rhs in
            if lhs.id.scenarioId.rawValue == rhs.id.scenarioId.rawValue {
                return lhs.id.seed.rawValue < rhs.id.seed.rawValue
            }
            return lhs.id.scenarioId.rawValue < rhs.id.scenarioId.rawValue
        }

        return RunRecord(output: output, scenarios: scenarios)
    }
}
