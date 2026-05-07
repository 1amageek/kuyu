import Foundation

public struct LearningCampaignArtifactRetentionSummary: Codable, Sendable, Equatable {
    public let mode: LearningCampaignArtifactRetentionMode
    public let seedCount: Int
    public let prunedCheckpointCount: Int
    public let prunedCandidateEvaluationArtifactCount: Int
    public let prunedByteCount: Int64
    public let records: [LearningCampaignArtifactRetentionRecord]

    public init(
        mode: LearningCampaignArtifactRetentionMode,
        records: [LearningCampaignArtifactRetentionRecord]
    ) {
        self.mode = mode
        self.seedCount = records.count
        self.prunedCheckpointCount = records.reduce(0) { $0 + $1.prunedCheckpointCount }
        self.prunedCandidateEvaluationArtifactCount = records.reduce(0) {
            $0 + $1.prunedCandidateEvaluationArtifactCount
        }
        self.prunedByteCount = records.reduce(0) { $0 + $1.prunedByteCount }
        self.records = records
    }
}
