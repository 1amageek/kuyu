import Foundation

public enum KuyuRegressionGatePolicy {
    public static func report(
        preflightFailure: String?,
        environmentTasks: [KuyuEnvironmentTaskReadiness],
        rolloutSuites: [KuyuRegressionRolloutEntry],
        failOnTruncation: Bool,
        minimumRewardAverage: Double?,
        qualityGateTask: String
    ) -> KuyuRegressionGateReport {
        let requirement = KuyuRegressionQualityGatePolicy.requirement(
            task: qualityGateTask,
            minimumRewardAverage: minimumRewardAverage
        )
        var reasons: [String] = []
        if let preflightFailure {
            reasons.append("preflight:\(preflightFailure)")
        }
        reasons.append(contentsOf: environmentTasks.filter { !$0.ready }.map { "environment-not-ready:\($0.task)" })
        if rolloutSuites.isEmpty {
            reasons.append("rollout-missing")
        }
        for entry in rolloutSuites {
            if entry.episodeCount == 0 {
                reasons.append("rollout-empty:\(entry.track)")
            }
            if entry.failureCount > 0 {
                reasons.append("rollout-failures:\(entry.track):\(entry.failureCount)")
            }
            if entry.cancelledCount > 0 {
                reasons.append("rollout-cancelled:\(entry.track):\(entry.cancelledCount)")
            }
            let taskPassRate = entry.episodeCount > 0
                ? Double(entry.taskPassCount) / Double(entry.episodeCount)
                : 0
            if requirement.requiresReferenceTaskPass && (entry.taskFailureCount > 0 || entry.taskPassCount != entry.episodeCount) {
                reasons.append("task-pass-mismatch:\(entry.track):\(entry.taskPassCount)/\(entry.episodeCount)")
            }
            if taskPassRate < requirement.minimumTaskPassRate {
                reasons.append("task-pass-rate-below-min:\(entry.track):\(taskPassRate)<\(requirement.minimumTaskPassRate)")
            }
            if failOnTruncation && entry.truncatedCount > 0 {
                reasons.append("truncated:\(entry.track):\(entry.truncatedCount)")
            }
            if let minimumRewardAverage = requirement.minimumRewardAverage, entry.rewardAverage < minimumRewardAverage {
                reasons.append("reward-average-below-min:\(entry.track):\(entry.rewardAverage)<\(minimumRewardAverage)")
            }
            reasons.append(contentsOf: entry.failureReasons.map { "rollout:\(entry.track):\($0)" })
            reasons.append(contentsOf: entry.taskFailureReasons.map { "task:\(entry.track):\($0)" })
        }
        return KuyuRegressionGateReport(
            accepted: reasons.isEmpty,
            reasons: Array(Set(reasons)).sorted(),
            failOnTruncation: failOnTruncation,
            minimumRewardAverage: minimumRewardAverage,
            qualityGateTask: qualityGateTask,
            qualityRequirement: requirement
        )
    }
}
