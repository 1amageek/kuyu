import Foundation
import KuyuScenarios

public struct KuyuRegressionArtifactValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case missingFile(String)
        case unsupportedSchemaVersion(Int)
        case emptyArtifactRoot
        case nonFiniteEnvironmentMetric(task: String)
        case invalidEnvironmentCount(task: String)
        case nonFiniteRolloutMetric(track: String)
        case invalidRolloutCount(track: String)
        case invalidTaskQualityCount(track: String, expected: Int, actual: Int)
        case nonFiniteTaskQuality(track: String, scenarioID: String)
        case invalidTaskQualityEvaluator(track: String, scenarioID: String, evaluatorID: String)
        case invalidWorkerSummary(track: String, workerIndex: Int)
        case workerSummaryMismatch(track: String)
        case gateReportMismatch(expected: [String], actual: [String])
        case gateAcceptedMismatch(expected: Bool, actual: Bool)
        case allPassedMismatch(expected: Bool, actual: Bool)
        case rolloutPassedMismatch(expected: Bool, actual: Bool)
    }

    public init() {}

    public func loadAndValidate(from artifactRoot: URL) throws -> KuyuRegressionSummary {
        let url = artifactRoot.appendingPathComponent("kuyu-regression-summary.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError.missingFile("kuyu-regression-summary.json")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let summary = try decoder.decode(KuyuRegressionSummary.self, from: Data(contentsOf: url))
        try validate(summary)
        return summary
    }

    public func validate(_ summary: KuyuRegressionSummary) throws {
        guard summary.schemaVersion == KuyuRegressionSummary.currentSchemaVersion else {
            throw ValidationError.unsupportedSchemaVersion(summary.schemaVersion)
        }
        guard !summary.artifactRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyArtifactRoot
        }
        try validateEnvironmentTasks(summary.environmentTasks)
        try validateRolloutSuites(summary.rolloutSuites)

        let expectedGateReport = KuyuRegressionGatePolicy.report(
            preflightFailure: summary.preflightFailure,
            environmentTasks: summary.environmentTasks,
            rolloutSuites: summary.rolloutSuites,
            failOnTruncation: summary.gateReport.failOnTruncation,
            minimumRewardAverage: summary.gateReport.minimumRewardAverage,
            qualityGateTask: summary.gateReport.qualityGateTask
        )
        guard expectedGateReport.qualityRequirement == summary.gateReport.qualityRequirement else {
            throw ValidationError.gateReportMismatch(
                expected: expectedGateReport.reasons,
                actual: summary.gateReport.reasons
            )
        }
        guard expectedGateReport.reasons == summary.gateReport.reasons else {
            throw ValidationError.gateReportMismatch(
                expected: expectedGateReport.reasons,
                actual: summary.gateReport.reasons
            )
        }
        guard expectedGateReport.accepted == summary.gateReport.accepted else {
            throw ValidationError.gateAcceptedMismatch(
                expected: expectedGateReport.accepted,
                actual: summary.gateReport.accepted
            )
        }
        guard summary.allPassed == summary.gateReport.accepted else {
            throw ValidationError.allPassedMismatch(
                expected: summary.gateReport.accepted,
                actual: summary.allPassed
            )
        }
        let expectedRolloutPassed = !summary.rolloutSuites.isEmpty
            && summary.rolloutSuites.allSatisfy { entry in
                entry.failureCount == 0
                    && entry.cancelledCount == 0
                    && entry.taskFailureCount == 0
                    && entry.taskPassCount == entry.episodeCount
                    && (!summary.gateReport.failOnTruncation || entry.truncatedCount == 0)
            }
        guard summary.rolloutPassed == expectedRolloutPassed else {
            throw ValidationError.rolloutPassedMismatch(
                expected: expectedRolloutPassed,
                actual: summary.rolloutPassed
            )
        }
    }

    private func validateEnvironmentTasks(_ tasks: [KuyuEnvironmentTaskReadiness]) throws {
        for task in tasks {
            guard task.score.isFinite,
                  task.safetyViolationSeconds.isFinite,
                  task.scenarioActionCoverage.isFinite,
                  task.stepActionCoverage.isFinite else {
                throw ValidationError.nonFiniteEnvironmentMetric(task: task.task)
            }
            guard task.scenarioCount >= 0,
                  task.logCount >= 0,
                  task.datasetScenarioCount >= 0,
                  task.failureCount >= 0 else {
                throw ValidationError.invalidEnvironmentCount(task: task.task)
            }
        }
    }

    private func validateRolloutSuites(_ rolloutSuites: [KuyuRegressionRolloutEntry]) throws {
        for entry in rolloutSuites {
            guard entry.rewardSum.isFinite, entry.rewardAverage.isFinite else {
                throw ValidationError.nonFiniteRolloutMetric(track: entry.track)
            }
            guard entry.episodeCount >= 0,
                  entry.doneCount >= 0,
                  entry.truncatedCount >= 0,
                  entry.failureCount >= 0,
                  entry.cancelledCount >= 0,
                  entry.taskPassCount >= 0,
                  entry.taskFailureCount >= 0,
                  entry.taskPassCount <= entry.episodeCount,
                  entry.taskFailureCount <= max(entry.episodeCount, max(entry.failureCount, entry.cancelledCount)) else {
                throw ValidationError.invalidRolloutCount(track: entry.track)
            }
            guard entry.taskQuality.count == entry.episodeCount else {
                throw ValidationError.invalidTaskQualityCount(
                    track: entry.track,
                    expected: entry.episodeCount,
                    actual: entry.taskQuality.count
                )
            }
            try validateTaskQuality(entry.taskQuality, track: entry.track)
            try validateWorkerSummaries(entry.workerSummaries, entry: entry)
        }
    }

    private func validateTaskQuality(
        _ summaries: [ReferenceQuadrotorTaskQualitySummary],
        track: String
    ) throws {
        for summary in summaries {
            guard summary.evaluatorID == KuyuRegressionQualityGatePolicy.qualityEvaluatorID else {
                throw ValidationError.invalidTaskQualityEvaluator(
                    track: track,
                    scenarioID: summary.scenarioID,
                    evaluatorID: summary.evaluatorID
                )
            }
            let numericValues = [
                summary.targetZ,
                summary.tolerance,
                summary.warmupTime,
                summary.requiredHoldTime,
                summary.achievedHoldTime,
                summary.maxAltitudeErrorAfterWarmup,
                summary.maxVerticalVelocityAfterWarmup
            ]
            guard numericValues.allSatisfy({ value in
                guard let value else { return true }
                return value.isFinite && value >= 0
            }) else {
                throw ValidationError.nonFiniteTaskQuality(track: track, scenarioID: summary.scenarioID)
            }
        }
    }

    private func validateWorkerSummaries(
        _ summaries: [KuyuRegressionWorkerSummary],
        entry: KuyuRegressionRolloutEntry
    ) throws {
        if entry.episodeCount == 0 {
            guard summaries.isEmpty else {
                throw ValidationError.workerSummaryMismatch(track: entry.track)
            }
            return
        }
        guard !summaries.isEmpty else {
            throw ValidationError.workerSummaryMismatch(track: entry.track)
        }

        var episodeCount = 0
        var doneCount = 0
        var truncatedCount = 0
        var failureCount = 0
        var cancelledCount = 0
        var rewardSum = 0.0
        var seenWorkers = Set<Int>()

        for summary in summaries {
            guard summary.workerIndex >= 0,
                  seenWorkers.insert(summary.workerIndex).inserted,
                  summary.episodeCount >= 0,
                  summary.doneCount >= 0,
                  summary.truncatedCount >= 0,
                  summary.failureCount >= 0,
                  summary.cancelledCount >= 0,
                  summary.rewardSum.isFinite,
                  summary.rewardAverage.isFinite,
                  summary.throughput.isFinite,
                  summary.throughput >= 0 else {
                throw ValidationError.invalidWorkerSummary(
                    track: entry.track,
                    workerIndex: summary.workerIndex
                )
            }
            episodeCount += summary.episodeCount
            doneCount += summary.doneCount
            truncatedCount += summary.truncatedCount
            failureCount += summary.failureCount
            cancelledCount += summary.cancelledCount
            rewardSum += summary.rewardSum
        }

        guard episodeCount == entry.episodeCount,
              doneCount == entry.doneCount,
              truncatedCount == entry.truncatedCount,
              failureCount == entry.failureCount,
              cancelledCount == entry.cancelledCount,
              abs(rewardSum - entry.rewardSum) <= 0.000_001 else {
            throw ValidationError.workerSummaryMismatch(track: entry.track)
        }
    }
}
