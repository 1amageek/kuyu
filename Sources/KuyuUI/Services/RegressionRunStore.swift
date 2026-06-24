import Foundation
import KuyuMLX
import KuyuScenarios

struct PostRegressionGateState: Sendable, Equatable {
    let artifactDirectory: URL
    let accepted: Bool
    let qualityTask: String
    let rolloutCount: Int
    let episodeCount: Int
    let rewardAverage: Double?
    let taskPassRate: Double?
    let achievedHoldTime: Double?
    let requiredHoldTime: Double?
    let minimumHoldTimeRatio: Double?
    let maxAltitudeErrorAfterWarmup: Double?
    let tolerance: Double?
    let maximumAltitudeErrorRatio: Double?
    let worstTrack: String?
    let worstScenarioID: String?
    let minimumWorkerThroughput: Double?
    let rejectReasons: [String]

    var primaryRejectReason: String? {
        rejectReasons.first
    }
}

struct RegressionRunStore: Sendable {
    private let loader: ReferenceQuadrotorRegressionArtifactLoader

    init(loader: ReferenceQuadrotorRegressionArtifactLoader = ReferenceQuadrotorRegressionArtifactLoader()) {
        self.loader = loader
    }

    func load(from artifactDirectory: URL) throws -> PostRegressionGateState {
        let summary = try loader.loadSummary(from: artifactDirectory)
        let totalEpisodes = summary.rolloutSuites.reduce(0) { $0 + $1.episodeCount }
        let totalReward = summary.rolloutSuites.reduce(0.0) { $0 + $1.rewardSum }
        let totalTaskPassCount = summary.rolloutSuites.reduce(0) { $0 + $1.taskPassCount }
        let minimumWorkerThroughput = summary.rolloutSuites
            .flatMap(\.workerSummaries)
            .map(\.throughput)
            .min()
        let qualitiesByTrack = summary.rolloutSuites.flatMap { entry in
            entry.taskQuality.map { quality in
                (track: entry.track, quality: quality)
            }
        }
        let worstHold = qualitiesByTrack
            .compactMap { item -> (track: String, quality: ReferenceQuadrotorTaskQualitySummary, ratio: Double)? in
                guard let achieved = item.quality.achievedHoldTime,
                      let required = item.quality.requiredHoldTime,
                      required > 0 else {
                    return nil
                }
                return (item.track, item.quality, achieved / required)
            }
            .min { lhs, rhs in
                lhs.ratio < rhs.ratio
            }
        let worstAltitude = qualitiesByTrack
            .compactMap { item -> (track: String, quality: ReferenceQuadrotorTaskQualitySummary, ratio: Double)? in
                guard let error = item.quality.maxAltitudeErrorAfterWarmup,
                      let tolerance = item.quality.tolerance,
                      tolerance > 0 else {
                    return nil
                }
                return (item.track, item.quality, error / tolerance)
            }
            .max { lhs, rhs in
                lhs.ratio < rhs.ratio
            }
        let worstQuality = worstAltitude?.quality ?? worstHold?.quality
        let worstTrack = worstAltitude?.track ?? worstHold?.track

        return PostRegressionGateState(
            artifactDirectory: artifactDirectory,
            accepted: summary.gateReport.accepted,
            qualityTask: summary.gateReport.qualityGateTask,
            rolloutCount: summary.rolloutSuites.count,
            episodeCount: totalEpisodes,
            rewardAverage: totalEpisodes > 0 ? totalReward / Double(totalEpisodes) : nil,
            taskPassRate: totalEpisodes > 0 ? Double(totalTaskPassCount) / Double(totalEpisodes) : nil,
            achievedHoldTime: worstHold?.quality.achievedHoldTime,
            requiredHoldTime: worstHold?.quality.requiredHoldTime,
            minimumHoldTimeRatio: worstHold?.ratio,
            maxAltitudeErrorAfterWarmup: worstAltitude?.quality.maxAltitudeErrorAfterWarmup,
            tolerance: worstAltitude?.quality.tolerance,
            maximumAltitudeErrorRatio: worstAltitude?.ratio,
            worstTrack: worstTrack,
            worstScenarioID: worstQuality?.scenarioID,
            minimumWorkerThroughput: minimumWorkerThroughput,
            rejectReasons: summary.gateReport.reasons
        )
    }
}
