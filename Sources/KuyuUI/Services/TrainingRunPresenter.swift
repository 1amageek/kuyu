import Foundation
import KuyuCore
import KuyuScenarios

struct TrainingRunCompletedPresentation {
    let record: RunRecord
    let scoreSample: MetricSample
    let overshootSample: MetricSample?
    let recoverySample: MetricSample?
    let hfSample: MetricSample?
    let terminalMetadata: [String: String]
}

struct TrainingRunPresenter {
    func runCompleted(
        iteration: Int,
        output: KuyAtt1RunOutput,
        score: Double
    ) -> TrainingRunCompletedPresentation {
        let iterationTime = Double(iteration)
        let aggregate = output.summary.aggregate
        let overshoot = aggregate.worstOvershootDegrees.map { String(format: "%.2f", $0) } ?? "n/a"
        let recovery = aggregate.averageRecoveryTime.map { String(format: "%.2f", $0) } ?? "n/a"
        let hf = aggregate.averageHfStabilityScore.map { String(format: "%.2f", $0) } ?? "n/a"
        return TrainingRunCompletedPresentation(
            record: buildRunRecord(output: output),
            scoreSample: MetricSample(time: iterationTime, value: score),
            overshootSample: aggregate.worstOvershootDegrees.map { MetricSample(time: iterationTime, value: $0) },
            recoverySample: aggregate.averageRecoveryTime.map { MetricSample(time: iterationTime, value: $0) },
            hfSample: aggregate.averageHfStabilityScore.map { MetricSample(time: iterationTime, value: $0) },
            terminalMetadata: [
                "iter": "\(iteration)",
                "score": String(format: "%.3f", score),
                "overshoot": overshoot,
                "recovery": recovery,
                "hf": hf,
            ]
        )
    }

    func buildRunRecord(output: KuyAtt1RunOutput) -> RunRecord {
        let evaluationsByKey = Dictionary(
            uniqueKeysWithValues: output.result.evaluations.map {
                (ScenarioKey(scenarioId: $0.scenarioId, seed: $0.seed), $0)
            }
        )

        let scenarios: [ScenarioRunRecord] = output.logs.compactMap { entry in
            guard let evaluation = evaluationsByKey[entry.key] else { return nil }
            let metrics = ScenarioMetricsBuilder.build(log: entry.log)
            return ScenarioRunRecord(
                id: entry.key,
                evaluation: evaluation,
                log: entry.log,
                metrics: metrics
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
