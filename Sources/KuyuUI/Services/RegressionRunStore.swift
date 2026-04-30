import Foundation
import KuyuMLX

struct PostRegressionGateState: Sendable, Equatable {
    let artifactDirectory: URL
    let accepted: Bool
    let qualityTask: String
    let rewardAverage: Double?
    let taskPassRate: Double?
    let achievedHoldTime: Double?
    let requiredHoldTime: Double?
    let maxAltitudeErrorAfterWarmup: Double?
    let tolerance: Double?
    let minimumWorkerThroughput: Double?
    let rejectReasons: [String]

    var primaryRejectReason: String? {
        rejectReasons.first
    }
}

struct RegressionRunStore: Sendable {
    private let validator: KuyuRegressionArtifactValidator

    init(validator: KuyuRegressionArtifactValidator = KuyuRegressionArtifactValidator()) {
        self.validator = validator
    }

    func load(from artifactDirectory: URL) throws -> PostRegressionGateState {
        let summary = try validator.loadAndValidate(from: artifactDirectory)
        let firstEntry = summary.rolloutSuites.first
        let firstQuality = firstEntry?.taskQuality.first
        let minimumWorkerThroughput = summary.rolloutSuites
            .flatMap(\.workerSummaries)
            .map(\.throughput)
            .min()
        let taskPassRate = firstEntry.flatMap { entry -> Double? in
            guard entry.episodeCount > 0 else { return nil }
            return Double(entry.taskPassCount) / Double(entry.episodeCount)
        }

        return PostRegressionGateState(
            artifactDirectory: artifactDirectory,
            accepted: summary.gateReport.accepted,
            qualityTask: summary.gateReport.qualityGateTask,
            rewardAverage: firstEntry?.rewardAverage,
            taskPassRate: taskPassRate,
            achievedHoldTime: firstQuality?.achievedHoldTime,
            requiredHoldTime: firstQuality?.requiredHoldTime,
            maxAltitudeErrorAfterWarmup: firstQuality?.maxAltitudeErrorAfterWarmup,
            tolerance: firstQuality?.tolerance,
            minimumWorkerThroughput: minimumWorkerThroughput,
            rejectReasons: summary.gateReport.reasons
        )
    }
}
