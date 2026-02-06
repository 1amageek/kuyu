import KuyuCore
import KuyuProfiles

public struct ScenarioRunRecord: Identifiable {
    public let id: ScenarioKey
    let evaluation: ScenarioEvaluation
    let log: SimulationLog
    let metrics: ScenarioMetrics
}
