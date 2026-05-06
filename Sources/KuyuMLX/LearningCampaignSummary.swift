import Foundation

public struct LearningCampaignSummary: Codable, Sendable, Equatable {
    public let artifactRoot: String
    public let seedCount: Int
    public let acceptedCount: Int
    public let finalCheckpoint: String
    public let runs: [LearningCampaignSeedRunSummary]
}
