import Foundation

public struct KuyuEnvironmentTaskReadiness: Sendable, Codable, Equatable {
    public let task: String
    public let controller: String
    public let ready: Bool
    public let suitePassed: Bool
    public let score: Double
    public let scenarioCount: Int
    public let logCount: Int
    public let datasetScenarioCount: Int
    public let failureCount: Int
    public let safetyViolationSeconds: Double
    public let scenarioActionCoverage: Double
    public let stepActionCoverage: Double
    public let artifactPath: String?
    public let failureReasons: [String]

    public init(
        task: String,
        controller: String,
        ready: Bool,
        suitePassed: Bool,
        score: Double,
        scenarioCount: Int,
        logCount: Int,
        datasetScenarioCount: Int,
        failureCount: Int,
        safetyViolationSeconds: Double,
        scenarioActionCoverage: Double,
        stepActionCoverage: Double,
        artifactPath: String?,
        failureReasons: [String]
    ) {
        self.task = task
        self.controller = controller
        self.ready = ready
        self.suitePassed = suitePassed
        self.score = score
        self.scenarioCount = scenarioCount
        self.logCount = logCount
        self.datasetScenarioCount = datasetScenarioCount
        self.failureCount = failureCount
        self.safetyViolationSeconds = safetyViolationSeconds
        self.scenarioActionCoverage = scenarioActionCoverage
        self.stepActionCoverage = stepActionCoverage
        self.artifactPath = artifactPath
        self.failureReasons = failureReasons
    }
}
