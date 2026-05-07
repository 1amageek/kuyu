import Foundation
import KuyuMLX
import KuyuScenarios
import Testing

@Test func regressionQualityGateAppliesLiftDefaultRewardMinimum() throws {
    let minimum = KuyuRegressionQualityGatePolicy.minimumRewardAverage(
        override: nil,
        task: "lift"
    )
    #expect(minimum == 0)

    let entry = makeRegressionRolloutEntry(rewardAverage: -1)
    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: minimum,
        qualityGateTask: "lift"
    )

    #expect(!report.accepted)
    #expect(report.qualityRequirement.evaluatorID == KuyuRegressionQualityGatePolicy.referenceEvaluatorID)
    #expect(report.qualityRequirement.qualityEvaluatorID == KuyuRegressionQualityGatePolicy.qualityEvaluatorID)
    #expect(report.qualityRequirement.minimumTaskPassRate == 1.0)
    #expect(report.qualityRequirement.minimumHoldTimeRatio == 1.0)
    #expect(report.qualityRequirement.liftThresholdSource == "scenario.liftEnvelope")
    #expect(report.reasons.contains("reward-average-below-min:lift-postRegression:-1.0<0.0"))
}

@Test func regressionArtifactValidatorReloadsAcceptedSummary() throws {
    let directory = temporaryDirectory()
    let entry = makeRegressionRolloutEntry(rewardAverage: 1)
    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )
    let summary = makeRegressionSummary(
        directory: directory,
        rolloutSuites: [entry],
        gateReport: report,
        allPassed: true
    )

    try write(summary, to: directory)

    let loaded = try KuyuRegressionArtifactValidator().loadAndValidate(from: directory)
    #expect(loaded == summary)
}

@Test func regressionArtifactValidatorRejectsGateMismatch() throws {
    let directory = temporaryDirectory()
    let entry = makeRegressionRolloutEntry(rewardAverage: -1)
    let invalidReport = KuyuRegressionGateReport(
        accepted: true,
        reasons: [],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift",
        qualityRequirement: KuyuRegressionQualityGatePolicy.requirement(
            task: "lift",
            minimumRewardAverage: 0
        )
    )
    let summary = makeRegressionSummary(
        directory: directory,
        rolloutSuites: [entry],
        gateReport: invalidReport,
        allPassed: true
    )

    try write(summary, to: directory)

    #expect(throws: KuyuRegressionArtifactValidator.ValidationError.self) {
        _ = try KuyuRegressionArtifactValidator().loadAndValidate(from: directory)
    }
}

@Test func regressionQualityGateRejectsMissingTaskQuality() throws {
    let entry = makeRegressionRolloutEntry(rewardAverage: 1, taskQuality: [])
    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )

    #expect(!report.accepted)
    #expect(report.reasons.contains("missing-task-quality:lift-postRegression:0/1"))
}

@Test func regressionQualityGateRejectsTaskQualityTaskMismatch() throws {
    let entry = makeRegressionRolloutEntry(
        rewardAverage: 1,
        taskQuality: [makeTaskQuality(task: "singleLift")]
    )
    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )

    #expect(!report.accepted)
    #expect(report.reasons.contains { $0.hasPrefix("task-quality-task-mismatch:lift-postRegression:") })
}

@Test func regressionQualityGateRejectsInsufficientLiftHoldTime() throws {
    let entry = makeRegressionRolloutEntry(
        rewardAverage: 1,
        taskQuality: [makeTaskQuality(achievedHoldTime: 0.5)]
    )
    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )

    #expect(!report.accepted)
    #expect(report.reasons.contains { $0.hasPrefix("hold-time-below-min:lift-postRegression:") })
}

@Test func regressionQualityGateRejectsAltitudeErrorAboveTolerance() throws {
    let entry = makeRegressionRolloutEntry(
        rewardAverage: 1,
        taskQuality: [makeTaskQuality(maxAltitudeErrorAfterWarmup: 0.3)]
    )
    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )

    #expect(!report.accepted)
    #expect(report.reasons.contains { $0.hasPrefix("altitude-error-above-tolerance:lift-postRegression:") })
}

@Test func regressionArtifactValidatorRejectsRolloutTaskQualityCountMismatch() throws {
    let directory = temporaryDirectory()
    let entry = makeRegressionRolloutEntry(rewardAverage: 1, taskQuality: [])
    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )
    let summary = makeRegressionSummary(
        directory: directory,
        rolloutSuites: [entry],
        gateReport: report,
        allPassed: false
    )

    try write(summary, to: directory)

    #expect(throws: KuyuRegressionArtifactValidator.ValidationError.self) {
        _ = try KuyuRegressionArtifactValidator().loadAndValidate(from: directory)
    }
}

@Test func regressionArtifactValidatorRejectsNonFiniteTaskQuality() throws {
    let directory = temporaryDirectory()
    let entry = makeRegressionRolloutEntry(
        rewardAverage: 1,
        taskQuality: [makeTaskQuality(maxAltitudeErrorAfterWarmup: .infinity)]
    )
    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )
    let summary = makeRegressionSummary(
        directory: directory,
        rolloutSuites: [entry],
        gateReport: report,
        allPassed: false
    )

    #expect(throws: KuyuRegressionArtifactValidator.ValidationError.self) {
        try KuyuRegressionArtifactValidator().validate(summary)
    }
}

@Test func regressionArtifactValidatorRejectsDuplicateTaskQualityKeys() throws {
    let directory = temporaryDirectory()
    let duplicate = makeTaskQuality()
    let entry = makeRegressionRolloutEntry(
        rewardAverage: 1,
        taskQuality: [duplicate, duplicate],
        episodeCount: 2,
        workerSummaries: [makeWorkerSummary(workerIndex: 0, episodeCount: 2, rewardSum: 2)]
    )
    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )
    let summary = makeRegressionSummary(
        directory: directory,
        rolloutSuites: [entry],
        gateReport: report,
        allPassed: report.accepted
    )

    #expect(throws: KuyuRegressionArtifactValidator.ValidationError.self) {
        try KuyuRegressionArtifactValidator().validate(summary)
    }
}

@Test func regressionArtifactValidatorRejectsTaskQualityEvaluatorMismatch() throws {
    let directory = temporaryDirectory()
    let entry = makeRegressionRolloutEntry(
        rewardAverage: 1,
        taskQuality: [makeTaskQuality(evaluatorID: "UnexpectedEvaluator")]
    )
    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )
    let summary = makeRegressionSummary(
        directory: directory,
        rolloutSuites: [entry],
        gateReport: report,
        allPassed: false
    )

    try write(summary, to: directory)

    #expect(throws: KuyuRegressionArtifactValidator.ValidationError.self) {
        _ = try KuyuRegressionArtifactValidator().loadAndValidate(from: directory)
    }
}

@Test func regressionArtifactValidatorRejectsTaskQualityTaskMismatch() throws {
    let directory = temporaryDirectory()
    let entry = makeRegressionRolloutEntry(
        rewardAverage: 1,
        taskQuality: [makeTaskQuality(task: "singleLift")]
    )
    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )
    let summary = makeRegressionSummary(
        directory: directory,
        rolloutSuites: [entry],
        gateReport: report,
        allPassed: false
    )

    try write(summary, to: directory)

    #expect(throws: KuyuRegressionArtifactValidator.ValidationError.self) {
        _ = try KuyuRegressionArtifactValidator().loadAndValidate(from: directory)
    }
}

@Test func regressionArtifactValidatorRejectsTamperedTaskQualityWithStaleGateReport() throws {
    let directory = temporaryDirectory()
    let acceptedEntry = makeRegressionRolloutEntry(rewardAverage: 1)
    let acceptedReport = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [acceptedEntry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )
    let tamperedEntry = makeRegressionRolloutEntry(
        rewardAverage: 1,
        taskQuality: [makeTaskQuality(achievedHoldTime: 0.1)]
    )
    let summary = makeRegressionSummary(
        directory: directory,
        rolloutSuites: [tamperedEntry],
        gateReport: acceptedReport,
        allPassed: true
    )

    try write(summary, to: directory)

    #expect(throws: KuyuRegressionArtifactValidator.ValidationError.self) {
        _ = try KuyuRegressionArtifactValidator().loadAndValidate(from: directory)
    }
}

@Test func regressionArtifactValidatorRejectsWorkerSummaryMismatch() throws {
    let directory = temporaryDirectory()
    let entry = makeRegressionRolloutEntry(
        rewardAverage: 1,
        workerSummaries: [
            makeWorkerSummary(workerIndex: 0, episodeCount: 1, rewardSum: 0.5)
        ]
    )
    let report = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [makeEnvironmentTask()],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: 0,
        qualityGateTask: "lift"
    )
    let summary = makeRegressionSummary(
        directory: directory,
        rolloutSuites: [entry],
        gateReport: report,
        allPassed: true
    )

    try write(summary, to: directory)

    #expect(throws: KuyuRegressionArtifactValidator.ValidationError.self) {
        _ = try KuyuRegressionArtifactValidator().loadAndValidate(from: directory)
    }
}

private func makeRegressionSummary(
    directory: URL,
    rolloutSuites: [KuyuRegressionRolloutEntry],
    gateReport: KuyuRegressionGateReport,
    allPassed: Bool
) -> KuyuRegressionSummary {
    KuyuRegressionSummary(
        artifactRoot: directory.path,
        startedAt: Date(timeIntervalSince1970: 0),
        controller: "teacherBaseline",
        environmentController: "teacherBaseline",
        snapshot: nil,
        preflightPassed: true,
        preflightFailure: nil,
        environmentReady: true,
        environmentTasks: [makeEnvironmentTask()],
        rolloutPassed: true,
        rolloutSuites: rolloutSuites,
        gateReport: gateReport,
        allPassed: allPassed
    )
}

private func makeEnvironmentTask() -> KuyuEnvironmentTaskReadiness {
    KuyuEnvironmentTaskReadiness(
        task: "lift",
        controller: "teacherBaseline",
        ready: true,
        suitePassed: true,
        score: 1,
        scenarioCount: 1,
        logCount: 1,
        datasetScenarioCount: 1,
        failureCount: 0,
        safetyViolationSeconds: 0,
        scenarioActionCoverage: 1,
        stepActionCoverage: 1,
        artifactPath: nil,
        failureReasons: []
    )
}

private func makeRegressionRolloutEntry(
    rewardAverage: Double,
    taskQuality: [ReferenceQuadrotorTaskQualitySummary]? = nil,
    episodeCount: Int = 1,
    workerSummaries: [KuyuRegressionWorkerSummary]? = nil
) -> KuyuRegressionRolloutEntry {
    KuyuRegressionRolloutEntry(
        suite: 6,
        track: "lift-postRegression",
        policyID: "test",
        episodeCount: episodeCount,
        rewardSum: rewardAverage * Double(episodeCount),
        rewardAverage: rewardAverage,
        doneCount: episodeCount,
        truncatedCount: 0,
        failureCount: 0,
        cancelledCount: 0,
        failureReasons: [],
        taskPassCount: episodeCount,
        taskFailureCount: 0,
        taskFailureReasons: [],
        taskQuality: taskQuality ?? [makeTaskQuality()],
        workerSummaries: workerSummaries ?? [
            makeWorkerSummary(workerIndex: 0, episodeCount: episodeCount, rewardSum: rewardAverage * Double(episodeCount))
        ],
        artifactPath: nil
    )
}

private func makeWorkerSummary(
    workerIndex: Int,
    episodeCount: Int,
    rewardSum: Double
) -> KuyuRegressionWorkerSummary {
    KuyuRegressionWorkerSummary(
        workerIndex: workerIndex,
        snapshotID: "snapshot-\(workerIndex)",
        rolloutShardPath: "/tmp/worker-\(workerIndex)",
        episodeCount: episodeCount,
        rewardSum: rewardSum,
        rewardAverage: episodeCount > 0 ? rewardSum / Double(episodeCount) : 0,
        throughput: 1,
        doneCount: episodeCount,
        truncatedCount: 0,
        failureCount: 0,
        cancelledCount: 0
    )
}

private func makeTaskQuality(
    task: String = "lift",
    passed: Bool = true,
    achievedHoldTime: Double = 1,
    maxAltitudeErrorAfterWarmup: Double = 0,
    evaluatorID: String = KuyuRegressionQualityGatePolicy.qualityEvaluatorID
) -> ReferenceQuadrotorTaskQualitySummary {
    ReferenceQuadrotorTaskQualitySummary(
        task: task,
        scenarioID: "KUY-TEST/LIFT",
        seed: 1,
        passed: passed,
        failureReasons: passed ? [] : ["lift-unsettled"],
        evaluatorID: evaluatorID,
        targetZ: 1,
        tolerance: 0.2,
        warmupTime: 0,
        requiredHoldTime: 1,
        achievedHoldTime: achievedHoldTime,
        maxAltitudeErrorAfterWarmup: maxAltitudeErrorAfterWarmup,
        maxVerticalVelocityAfterWarmup: 0
    )
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-regression-artifact-\(UUID().uuidString)", isDirectory: true)
}

private func write(_ summary: KuyuRegressionSummary, to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(summary).write(
        to: directory.appendingPathComponent("kuyu-regression-summary.json"),
        options: [.atomic]
    )
}
