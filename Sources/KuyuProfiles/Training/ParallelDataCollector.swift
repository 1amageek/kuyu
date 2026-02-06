import KuyuCore

public struct ParallelDataCollector {
    public let buffer: OnlineDataBuffer
    public let evaluator: ExtendedScenarioEvaluator

    public init(buffer: OnlineDataBuffer, evaluator: ExtendedScenarioEvaluator = ExtendedScenarioEvaluator()) {
        self.buffer = buffer
        self.evaluator = evaluator
    }

    public struct CollectionResult: Sendable {
        public let recordsCollected: Int
        public let evaluations: [ExtendedScenarioEvaluation]

        public init(recordsCollected: Int, evaluations: [ExtendedScenarioEvaluation]) {
            self.recordsCollected = recordsCollected
            self.evaluations = evaluations
        }
    }

    public func collect(
        logs: [SimulationLog],
        definitions: [ReferenceQuadrotorScenarioDefinition]
    ) -> CollectionResult {
        var evaluations: [ExtendedScenarioEvaluation] = []
        var totalRecords = 0

        for (log, definition) in zip(logs, definitions) {
            buffer.appendFromLog(log)
            totalRecords += log.events.count
            let evaluation = evaluator.evaluate(definition: definition, log: log)
            evaluations.append(evaluation)
        }

        return CollectionResult(
            recordsCollected: totalRecords,
            evaluations: evaluations
        )
    }
}
