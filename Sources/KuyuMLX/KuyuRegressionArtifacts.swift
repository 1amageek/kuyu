import Foundation

public struct KuyuRegressionGateReport: Sendable, Codable, Equatable {
    public let accepted: Bool
    public let reasons: [String]
    public let failOnTruncation: Bool
    public let minimumRewardAverage: Double?
    public let qualityGateTask: String
    public let qualityRequirement: KuyuRegressionQualityRequirement

    public init(
        accepted: Bool,
        reasons: [String],
        failOnTruncation: Bool,
        minimumRewardAverage: Double?,
        qualityGateTask: String,
        qualityRequirement: KuyuRegressionQualityRequirement
    ) {
        self.accepted = accepted
        self.reasons = reasons
        self.failOnTruncation = failOnTruncation
        self.minimumRewardAverage = minimumRewardAverage
        self.qualityGateTask = qualityGateTask
        self.qualityRequirement = qualityRequirement
    }
}

public struct KuyuRegressionQualityRequirement: Sendable, Codable, Equatable {
    public let task: String
    public let evaluatorID: String
    public let requiresReferenceTaskPass: Bool
    public let minimumTaskPassRate: Double
    public let minimumRewardAverage: Double?
    public let liftThresholdSource: String?

    public init(
        task: String,
        evaluatorID: String,
        requiresReferenceTaskPass: Bool,
        minimumTaskPassRate: Double,
        minimumRewardAverage: Double?,
        liftThresholdSource: String?
    ) {
        self.task = task
        self.evaluatorID = evaluatorID
        self.requiresReferenceTaskPass = requiresReferenceTaskPass
        self.minimumTaskPassRate = minimumTaskPassRate
        self.minimumRewardAverage = minimumRewardAverage
        self.liftThresholdSource = liftThresholdSource
    }
}

public struct KuyuRegressionSummary: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let artifactRoot: String
    public let startedAt: Date
    public let controller: String
    public let environmentController: String
    public let snapshot: String?
    public let preflightPassed: Bool
    public let preflightFailure: String?
    public let environmentReady: Bool
    public let environmentTasks: [KuyuEnvironmentTaskReadiness]
    public let rolloutPassed: Bool
    public let rolloutSuites: [KuyuRegressionRolloutEntry]
    public let gateReport: KuyuRegressionGateReport
    public let allPassed: Bool

    public init(
        schemaVersion: Int = KuyuRegressionSummary.currentSchemaVersion,
        artifactRoot: String,
        startedAt: Date,
        controller: String,
        environmentController: String,
        snapshot: String?,
        preflightPassed: Bool,
        preflightFailure: String?,
        environmentReady: Bool,
        environmentTasks: [KuyuEnvironmentTaskReadiness],
        rolloutPassed: Bool,
        rolloutSuites: [KuyuRegressionRolloutEntry],
        gateReport: KuyuRegressionGateReport,
        allPassed: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.artifactRoot = artifactRoot
        self.startedAt = startedAt
        self.controller = controller
        self.environmentController = environmentController
        self.snapshot = snapshot
        self.preflightPassed = preflightPassed
        self.preflightFailure = preflightFailure
        self.environmentReady = environmentReady
        self.environmentTasks = environmentTasks
        self.rolloutPassed = rolloutPassed
        self.rolloutSuites = rolloutSuites
        self.gateReport = gateReport
        self.allPassed = allPassed
    }
}

public struct KuyuRegressionRolloutEntry: Sendable, Codable, Equatable {
    public let suite: Int
    public let track: String
    public let policyID: String
    public let episodeCount: Int
    public let rewardSum: Double
    public let rewardAverage: Double
    public let doneCount: Int
    public let truncatedCount: Int
    public let failureCount: Int
    public let cancelledCount: Int
    public let failureReasons: [String]
    public let taskPassCount: Int
    public let taskFailureCount: Int
    public let taskFailureReasons: [String]
    public let artifactPath: String?

    public init(
        suite: Int,
        track: String,
        policyID: String,
        episodeCount: Int,
        rewardSum: Double,
        rewardAverage: Double,
        doneCount: Int,
        truncatedCount: Int,
        failureCount: Int,
        cancelledCount: Int,
        failureReasons: [String],
        taskPassCount: Int,
        taskFailureCount: Int,
        taskFailureReasons: [String],
        artifactPath: String?
    ) {
        self.suite = suite
        self.track = track
        self.policyID = policyID
        self.episodeCount = episodeCount
        self.rewardSum = rewardSum
        self.rewardAverage = rewardAverage
        self.doneCount = doneCount
        self.truncatedCount = truncatedCount
        self.failureCount = failureCount
        self.cancelledCount = cancelledCount
        self.failureReasons = failureReasons
        self.taskPassCount = taskPassCount
        self.taskFailureCount = taskFailureCount
        self.taskFailureReasons = taskFailureReasons
        self.artifactPath = artifactPath
    }
}
