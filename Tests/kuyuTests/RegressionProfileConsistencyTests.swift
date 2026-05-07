import KuyuMLX
import KuyuScenarios
import KuyuTraining
import Testing

@Test func regressionQualityRequirementMirrorsTaskEvaluationProfile() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let minimumRewardAverage = KuyuRegressionQualityGatePolicy.minimumRewardAverage(
        override: nil,
        task: profile.task
    )
    let requirement = KuyuRegressionQualityGatePolicy.requirement(
        task: profile.task,
        minimumRewardAverage: minimumRewardAverage
    )

    #expect(requirement.task == profile.task)
    #expect(requirement.evaluatorID == profile.referenceEvaluatorID)
    #expect(requirement.qualityEvaluatorID == profile.qualityEvaluatorID)
    #expect(requirement.requiresReferenceTaskPass == profile.requiresReferenceTaskPass)
    #expect(requirement.minimumTaskPassRate == profile.minimumTaskPassRate)
    #expect(requirement.minimumRewardAverage == profile.minimumRewardAverage)
    #expect(requirement.minimumHoldTimeRatio == (profile.minimumHoldTimeRatio ?? 1.0))
    #expect(requirement.liftThresholdSource == profile.liftThresholdSource)
}

@Test func regressionGateRejectsTaskQualityFromDifferentProfile() {
    let entry = makeRegressionRolloutEntry(
        quality: ReferenceQuadrotorTaskQualitySummary(
            task: "singleLift",
            scenarioID: "singleLift-fixture",
            seed: 1,
            passed: true,
            failureReasons: [],
            evaluatorID: "ReferenceQuadrotorTaskQualityEvaluator",
            targetZ: 1,
            tolerance: 0.1,
            warmupTime: 0,
            requiredHoldTime: 1,
            achievedHoldTime: 1,
            maxAltitudeErrorAfterWarmup: 0,
            maxVerticalVelocityAfterWarmup: 0
        )
    )

    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )

    #expect(!report.accepted)
    #expect(report.reasons.contains { $0.contains("task-quality-task-mismatch") })
}

private func makeRegressionRolloutEntry(
    quality: ReferenceQuadrotorTaskQualitySummary
) -> KuyuRegressionRolloutEntry {
    KuyuRegressionRolloutEntry(
        suite: 6,
        track: "long-horizon-task",
        policyID: "test-policy",
        episodeCount: 1,
        rewardSum: 1,
        rewardAverage: 1,
        doneCount: 1,
        truncatedCount: 0,
        failureCount: 0,
        cancelledCount: 0,
        failureReasons: [],
        taskPassCount: 1,
        taskFailureCount: 0,
        taskFailureReasons: [],
        taskQuality: [quality],
        workerSummaries: [],
        artifactPath: nil
    )
}
