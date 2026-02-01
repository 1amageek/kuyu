public struct ValidationSummary: Sendable, Codable, Equatable {
    public let suitePassed: Bool
    public let evaluations: [ScenarioEvaluation]
    public let replayChecks: [ReplayCheckResult]
    public let manifest: [ScenarioManifest]

    public init(
        suitePassed: Bool,
        evaluations: [ScenarioEvaluation],
        replayChecks: [ReplayCheckResult],
        manifest: [ScenarioManifest]
    ) {
        self.suitePassed = suitePassed
        self.evaluations = evaluations
        self.replayChecks = replayChecks
        self.manifest = manifest
    }
}
