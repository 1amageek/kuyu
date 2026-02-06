import KuyuCore

public struct KuyAtt1RunOutput: Sendable, Codable, Equatable {
    public let result: SuiteRunResult
    public let summary: ValidationSummary
    public let logs: [ScenarioLogEntry]

    public init(
        result: SuiteRunResult,
        summary: ValidationSummary,
        logs: [ScenarioLogEntry]
    ) {
        self.result = result
        self.summary = summary
        self.logs = logs
    }
}
