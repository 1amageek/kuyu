import Foundation
import KuyuMLX
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
    #expect(report.qualityRequirement.minimumTaskPassRate == 1.0)
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

private func makeRegressionRolloutEntry(rewardAverage: Double) -> KuyuRegressionRolloutEntry {
    KuyuRegressionRolloutEntry(
        suite: 6,
        track: "lift-postRegression",
        policyID: "test",
        episodeCount: 1,
        rewardSum: rewardAverage,
        rewardAverage: rewardAverage,
        doneCount: 1,
        truncatedCount: 0,
        failureCount: 0,
        cancelledCount: 0,
        failureReasons: [],
        taskPassCount: 1,
        taskFailureCount: 0,
        taskFailureReasons: [],
        artifactPath: nil
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
