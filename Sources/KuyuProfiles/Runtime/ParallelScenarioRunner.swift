import KuyuCore

public struct ParallelScenarioRunner<Runner: PlantScenarioRunner> {
    public let runner: Runner
    public let maxConcurrency: Int

    public init(runner: Runner, maxConcurrency: Int = 4) {
        self.runner = runner
        self.maxConcurrency = maxConcurrency
    }

    @MainActor
    public func runAll(
        definitions: [Runner.Scenario],
        cutFactory: (Runner.Scenario) throws -> Runner.Cut,
        motorNerveFactory: ((Runner.Scenario) throws -> Runner.Nerve?)? = nil,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [SimulationLog] {
        var results: [SimulationLog] = []
        let total = definitions.count
        for (index, definition) in definitions.enumerated() {
            let cut = try cutFactory(definition)
            let nerve: Runner.Nerve?
            if let factory = motorNerveFactory {
                nerve = try factory(definition)
            } else {
                nerve = nil
            }
            let log = try await runner.runScenario(
                definition: definition,
                cut: cut,
                motorNerve: nerve,
                control: nil,
                telemetry: nil
            )
            results.append(log)
            onProgress?(index + 1, total)
            await Task.yield()
        }
        return results
    }
}
