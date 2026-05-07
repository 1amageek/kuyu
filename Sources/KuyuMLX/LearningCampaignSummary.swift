import Foundation

public struct LearningCampaignSummary: Codable, Sendable, Equatable {
    public let artifactRoot: String
    public let seedCount: Int
    public let acceptedCount: Int
    public let finalCheckpoint: String
    public let runs: [LearningCampaignSeedRunSummary]
    public let retention: LearningCampaignArtifactRetentionSummary?

    public init(
        artifactRoot: String,
        seedCount: Int,
        acceptedCount: Int,
        finalCheckpoint: String,
        runs: [LearningCampaignSeedRunSummary],
        retention: LearningCampaignArtifactRetentionSummary? = nil
    ) {
        self.artifactRoot = artifactRoot
        self.seedCount = seedCount
        self.acceptedCount = acceptedCount
        self.finalCheckpoint = finalCheckpoint
        self.runs = runs
        self.retention = retention
    }
}
