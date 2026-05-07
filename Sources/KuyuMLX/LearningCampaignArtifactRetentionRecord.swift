import Foundation

public struct LearningCampaignArtifactRetentionRecord: Codable, Sendable, Equatable {
    public let seed: String
    public let mode: LearningCampaignArtifactRetentionMode
    public let prunedCheckpointCount: Int
    public let prunedCandidateEvaluationArtifactCount: Int
    public let prunedByteCount: Int64
    public let preservedCheckpointPaths: [String]

    public init(
        seed: String,
        mode: LearningCampaignArtifactRetentionMode,
        prunedCheckpointCount: Int,
        prunedCandidateEvaluationArtifactCount: Int,
        prunedByteCount: Int64,
        preservedCheckpointPaths: [String]
    ) {
        self.seed = seed
        self.mode = mode
        self.prunedCheckpointCount = max(0, prunedCheckpointCount)
        self.prunedCandidateEvaluationArtifactCount = max(0, prunedCandidateEvaluationArtifactCount)
        self.prunedByteCount = max(0, prunedByteCount)
        self.preservedCheckpointPaths = preservedCheckpointPaths.sorted()
    }
}
