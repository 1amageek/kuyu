import KuyuCore

/// Orchestrates the full generate-run-evaluate-collect training loop.
///
/// Integrates ParametricScenarioGenerator, ParallelScenarioRunner,
/// ExtendedScenarioEvaluator, ParallelDataCollector, and CurriculumController
/// into a single iterative pipeline.
public struct AutomatedTrainingPipeline<Runner: PlantScenarioRunner>
where Runner.Scenario == ReferenceQuadrotorScenarioDefinition {

    public struct IterationResult: Sendable {
        public let level: Int
        public let scenariosRun: Int
        public let passRate: Double
        public let recordsCollected: Int
        public let advanceResult: CurriculumController.AdvanceResult
        public let evaluations: [ExtendedScenarioEvaluation]
        public let labels: [AutoLabeler.LabeledResult]

        public init(
            level: Int,
            scenariosRun: Int,
            passRate: Double,
            recordsCollected: Int,
            advanceResult: CurriculumController.AdvanceResult,
            evaluations: [ExtendedScenarioEvaluation],
            labels: [AutoLabeler.LabeledResult]
        ) {
            self.level = level
            self.scenariosRun = scenariosRun
            self.passRate = passRate
            self.recordsCollected = recordsCollected
            self.advanceResult = advanceResult
            self.evaluations = evaluations
            self.labels = labels
        }
    }

    public let generator: ParametricScenarioGenerator
    public var curriculum: CurriculumController
    public let buffer: OnlineDataBuffer
    public let labeler: AutoLabeler
    public let scenarioRunner: ParallelScenarioRunner<Runner>
    public let collector: ParallelDataCollector

    public init(
        generator: ParametricScenarioGenerator,
        curriculum: CurriculumController,
        buffer: OnlineDataBuffer,
        labeler: AutoLabeler = AutoLabeler(),
        scenarioRunner: ParallelScenarioRunner<Runner>,
        collector: ParallelDataCollector
    ) {
        self.generator = generator
        self.curriculum = curriculum
        self.buffer = buffer
        self.labeler = labeler
        self.scenarioRunner = scenarioRunner
        self.collector = collector
    }

    /// Run a single pipeline iteration: generate scenarios, execute, evaluate, collect data.
    @MainActor
    public mutating func runIteration(
        cutFactory: (ReferenceQuadrotorScenarioDefinition) throws -> Runner.Cut,
        motorNerveFactory: ((ReferenceQuadrotorScenarioDefinition) throws -> Runner.Nerve?)? = nil,
        iterationSeed: UInt64,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> IterationResult {
        let level = curriculum.currentLevel

        // 1. Generate scenarios for current difficulty level
        let allLevels = try generator.generateCurriculum(
            levels: curriculum.config.totalLevels,
            scenariosPerLevel: curriculum.config.scenariosPerLevel,
            baseSeed: iterationSeed
        )

        let definitions: [ReferenceQuadrotorScenarioDefinition]
        if level < allLevels.count {
            definitions = allLevels[level]
        } else {
            definitions = allLevels.last ?? []
        }

        // 2. Run scenarios
        let logs = try await scenarioRunner.runAll(
            definitions: definitions,
            cutFactory: cutFactory,
            motorNerveFactory: motorNerveFactory,
            onProgress: onProgress
        )

        // 3. Collect data and evaluate
        let collectionResult = collector.collect(logs: logs, definitions: definitions)

        // 4. Label results
        let labels = labeler.labelAll(evaluations: collectionResult.evaluations)

        // 5. Report to curriculum controller
        let passCount = collectionResult.evaluations.filter(\.base.passed).count
        let passRate = definitions.isEmpty ? 0 : Double(passCount) / Double(definitions.count)
        let advanceResult = curriculum.report(evaluations: collectionResult.evaluations)

        return IterationResult(
            level: level,
            scenariosRun: definitions.count,
            passRate: passRate,
            recordsCollected: collectionResult.recordsCollected,
            advanceResult: advanceResult,
            evaluations: collectionResult.evaluations,
            labels: labels
        )
    }

    /// Whether the curriculum has completed all levels.
    public var isComplete: Bool {
        curriculum.isComplete
    }
}
