import KuyuCore

public protocol ScenarioEvaluating {
    associatedtype Scenario

    func evaluate(definition: Scenario, log: SimulationLog) -> ScenarioEvaluation
}
