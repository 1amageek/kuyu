import KuyuCore

public protocol PlantScenarioRunner {
    associatedtype Scenario
    associatedtype Cut: CutInterface
    associatedtype Nerve: MotorNerveEndpoint

    @MainActor
    func runScenario(
        definition: Scenario,
        cut: Cut,
        motorNerve: Nerve?,
        control: SimulationControl?,
        telemetry: ((WorldStepLog) -> Void)?
    ) async throws -> SimulationLog
}
