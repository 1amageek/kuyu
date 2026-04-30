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
            if entry.taskQuality.count != entry.episodeCount {
                reasons.append("missing-task-quality:\(entry.track):\(entry.taskQuality.count)/\(entry.episodeCount)")
            }
            reasons.append(contentsOf: qualityReasons(for: entry, requirement: requirement))
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

    private static func qualityReasons(
        for entry: KuyuRegressionRolloutEntry,
        requirement: KuyuRegressionQualityRequirement
    ) -> [String] {
        var reasons: [String] = []
        for quality in entry.taskQuality {
            if quality.evaluatorID != requirement.qualityEvaluatorID {
                reasons.append("task-quality-evaluator-mismatch:\(entry.track):\(quality.scenarioID)")
            }
            if quality.passed == false {
                reasons.append("task-quality-failed:\(entry.track):\(quality.scenarioID)")
            }
            guard quality.task == "lift" || quality.task == "singleLift" else {
                continue
            }
            guard let achievedHoldTime = quality.achievedHoldTime,
                  let requiredHoldTime = quality.requiredHoldTime,
                  let tolerance = quality.tolerance,
                  let maxAltitudeError = quality.maxAltitudeErrorAfterWarmup else {
                reasons.append("missing-task-quality:\(entry.track):\(quality.scenarioID)")
                continue
            }
            let requiredHoldTimeWithRatio = requiredHoldTime * requirement.minimumHoldTimeRatio
            if achievedHoldTime < requiredHoldTimeWithRatio {
                reasons.append("hold-time-below-min:\(entry.track):\(quality.scenarioID):\(achievedHoldTime)<\(requiredHoldTimeWithRatio)")
            }
            if maxAltitudeError > tolerance {
                reasons.append("altitude-error-above-tolerance:\(entry.track):\(quality.scenarioID):\(maxAltitudeError)>\(tolerance)")
            }
        }
        return reasons
    }
}
