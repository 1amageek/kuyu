import KuyuCore

public struct ScenarioLogBundle: Sendable, Codable, Equatable {
    public let summary: ValidationSummary
    public let manifest: [ReferenceQuadrotorScenarioManifest]
    public let evaluations: [ScenarioEvaluation]
    public let replayChecks: [ReplayCheckResult]
    public let logs: [ScenarioLogIndex]

    public init(
        summary: ValidationSummary,
        manifest: [ReferenceQuadrotorScenarioManifest],
        evaluations: [ScenarioEvaluation],
        replayChecks: [ReplayCheckResult],
        logs: [ScenarioLogIndex]
    ) {
        self.summary = summary
        self.manifest = manifest
        self.evaluations = evaluations
        self.replayChecks = replayChecks
        self.logs = logs
    }
}
