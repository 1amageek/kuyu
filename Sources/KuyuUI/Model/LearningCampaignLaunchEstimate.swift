import Foundation

struct LearningCampaignLaunchEstimate: Sendable, Equatable {
    var candidateEvaluations: Int
    var regressionRollouts: Int
    var regressionEpisodes: Int
    var workerCount: Int
    var candidateConcurrency: Int
    var retention: String
    var estimatedAt: Date

    var scaleLabel: String {
        if regressionEpisodes >= 10_000 {
            return "large"
        }
        if regressionEpisodes >= 1_000 {
            return "medium"
        }
        return "small"
    }

    var parallelismLabel: String {
        "\(workerCount) workers / \(candidateConcurrency) candidates"
    }
}
