import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuScenarios
import KuyuTraining

func writeRegressionMatrixSummary(
    _ summary: ReferenceQuadrotorRegressionMatrixSummary,
    to artifactRoot: URL
) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(summary).write(
        to: artifactRoot.appendingPathComponent(ReferenceQuadrotorRegressionMatrixSummary.fileName),
        options: [.atomic]
    )
}

func runKuyuRegression(
    controller selectedController: ControllerSelection,
    snapshotURL: URL?,
    tier: TierChoice,
    cutPeriodSteps: UInt64,
    tasks selectedTasks: [SimulationTaskMode],
    suites selectedSuites: [Int],
    episodes: Int,
    workers: Int,
    maxSteps: Int?,
    maxWallTime: Double?,
    model: String,
    artifactRoot: URL,
    kp: Double,
    kd: Double,
    yawDamping: Double,
    hoverScale: Double,
    failOnTruncation: Bool,
    minimumRewardAverage: Double?,
    useQualityGating: Bool
) async throws -> ReferenceQuadrotorRegressionSummary {
    let rolloutTask = regressionRolloutTask(selectedTasks)
    let environmentTasks = selectedTasks.map { task in
        learningCampaignRolloutTask(from: rolloutTaskChoice(from: task))
    }
    let summary = try await ReferenceQuadrotorRegressionRunner().run(
        config: ReferenceQuadrotorRegressionRunConfig(
            controller: selectedController,
            snapshotURL: snapshotURL,
            tier: learningCampaignTier(from: tier),
            cutPeriodSteps: cutPeriodSteps,
            task: learningCampaignRolloutTask(from: rolloutTask),
            environmentTasks: environmentTasks,
            suites: selectedSuites,
            episodes: episodes,
            workers: workers,
            maxSteps: maxSteps,
            maxWallTime: maxWallTime,
            robotManifestPath: model,
            artifactRoot: artifactRoot,
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverScale: hoverScale,
            failOnTruncation: failOnTruncation,
            minimumRewardAverage: minimumRewardAverage,
            useQualityGating: useQualityGating
        )
    )
    for entry in summary.rolloutSuites {
        if entry.episodeCount == 0, !entry.failureReasons.isEmpty {
            print("[regression] suite=\(entry.suite) track=\(entry.track) failed reason=\(entry.failureReasons.joined(separator: " | "))")
        } else {
            print("[regression] suite=\(entry.suite) track=\(entry.track) episodes=\(entry.episodeCount) workers=\(entry.workerSummaries.count) rewardAvg=\(String(format: "%.3f", entry.rewardAverage)) failures=\(entry.failureCount) taskFailures=\(entry.taskFailureCount) taskPassRate=\(String(format: "%.3f", regressionTaskPassRate(entry))) truncated=\(entry.truncatedCount) \(regressionQualityText(entry.taskQuality)) \(regressionWorkerText(entry.workerSummaries))")
        }
    }
    return summary
}

func regressionSnapshotURL(_ raw: String, controller: ControllerSelection) throws -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard controller == .manasMLX else {
        return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed, isDirectory: true)
    }
    guard !trimmed.isEmpty else {
        throw ValidationError("--snapshot is required when --controller manasMLX.")
    }
    return URL(fileURLWithPath: trimmed, isDirectory: true)
}

func parseRegressionSuites(_ raw: String) throws -> [Int] {
    let values = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !values.isEmpty else {
        throw ValidationError("--suites must include at least one suite.")
    }
    var seenSuites = Set<Int>()
    return try values.map { value in
        guard let suite = Int(value), (0...8).contains(suite) else {
            throw ValidationError("--suites supports 0-8 (attitude 0-5 = A1 conformance suites, 6-8 = long-horizon tracks).")
        }
        guard seenSuites.insert(suite).inserted else {
            throw ValidationError("--suites contains a duplicate suite: \(suite)")
        }
        return suite
    }
}

func regressionTaskPassRate(_ entry: ReferenceQuadrotorRegressionRolloutEntry) -> Double {
    guard entry.episodeCount > 0 else { return 0 }
    return Double(entry.taskPassCount) / Double(entry.episodeCount)
}

func regressionQualityText(_ summaries: [ReferenceQuadrotorTaskQualitySummary]) -> String {
    guard let summary = summaries.first else {
        return "qualityGateTask=missing"
    }
    let hold = formattedRatio(
        achieved: summary.achievedHoldTime,
        required: summary.requiredHoldTime
    )
    let altitudeError = summary.maxAltitudeErrorAfterWarmup.map { String(format: "%.3f", $0) } ?? "--"
    let tolerance = summary.tolerance.map { String(format: "%.3f", $0) } ?? "--"
    return "qualityGateTask=\(summary.task) achievedHoldTime=\(hold.achieved) requiredHoldTime=\(hold.required) maxAltitudeErrorAfterWarmup=\(altitudeError) tolerance=\(tolerance)"
}

func regressionWorkerText(_ summaries: [ReferenceQuadrotorRegressionWorkerSummary]) -> String {
    guard let slowest = summaries.min(by: { lhs, rhs in lhs.throughput < rhs.throughput }) else {
        return "workerThroughput=missing"
    }
    return "workerThroughputMin=\(String(format: "%.3f", slowest.throughput))"
}

func formattedRatio(achieved: Double?, required: Double?) -> (achieved: String, required: String) {
    let achievedText = achieved.map { String(format: "%.3f", $0) } ?? "--"
    let requiredText = required.map { String(format: "%.3f", $0) } ?? "--"
    return (achievedText, requiredText)
}

func regressionRolloutTask(_ selectedTasks: [SimulationTaskMode]) -> RolloutTaskChoice {
    guard selectedTasks.count == 1, let task = selectedTasks.first else {
        return .attitude
    }
    return rolloutTaskChoice(from: task)
}

func rolloutTaskChoice(from task: SimulationTaskMode) -> RolloutTaskChoice {
    switch task {
    case .attitude:
        return .attitude
    case .lift:
        return .lift
    case .singleLift:
        return .singleLift
    }
}
