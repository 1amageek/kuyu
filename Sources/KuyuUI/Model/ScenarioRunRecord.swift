import KuyuCore
import KuyuPhysics
import KuyuScenarios

public struct ScenarioRunRecord: Identifiable {
    public let id: ScenarioKey
    let evaluation: ScenarioEvaluation
    let log: SimulationLog
    let metrics: ScenarioMetrics
}
