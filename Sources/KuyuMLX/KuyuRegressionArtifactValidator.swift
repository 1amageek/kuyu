import Foundation

public struct KuyuRegressionArtifactValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case missingFile(String)
        case unsupportedSchemaVersion(Int)
        case emptyArtifactRoot
        case nonFiniteEnvironmentMetric(task: String)
        case invalidEnvironmentCount(task: String)
        case nonFiniteRolloutMetric(track: String)
        case invalidRolloutCount(track: String)
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
                  entry.taskFailureCount <= entry.episodeCount else {
                throw ValidationError.invalidRolloutCount(track: entry.track)
            }
        }
    }
}
