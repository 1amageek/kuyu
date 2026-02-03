import KuyuCore

struct ScenarioRunRecord: Identifiable {
    let id: ScenarioKey
    let evaluation: ScenarioEvaluation
    let log: SimulationLog
    let metrics: ScenarioMetrics
}
