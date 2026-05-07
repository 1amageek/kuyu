import Foundation

public struct LearningCampaignArtifactRetentionPolicy: Codable, Sendable, Equatable {
    public let mode: LearningCampaignArtifactRetentionMode
    public let keepAcceptedCheckpoints: Bool
    public let keepIncumbentCheckpoints: Bool
    public let keepBestCandidateCheckpoints: Bool
    public let keepCandidateEvaluationArtifacts: Bool

    public init(
        mode: LearningCampaignArtifactRetentionMode = .full,
        keepAcceptedCheckpoints: Bool = true,
        keepIncumbentCheckpoints: Bool = true,
        keepBestCandidateCheckpoints: Bool = true,
        keepCandidateEvaluationArtifacts: Bool = true
    ) {
        self.mode = mode
        self.keepAcceptedCheckpoints = keepAcceptedCheckpoints
        self.keepIncumbentCheckpoints = keepIncumbentCheckpoints
        self.keepBestCandidateCheckpoints = keepBestCandidateCheckpoints
        self.keepCandidateEvaluationArtifacts = keepCandidateEvaluationArtifacts
    }

    public static let full = LearningCampaignArtifactRetentionPolicy()

    public static let compact = LearningCampaignArtifactRetentionPolicy(
        mode: .compact,
        keepAcceptedCheckpoints: true,
        keepIncumbentCheckpoints: false,
        keepBestCandidateCheckpoints: true,
        keepCandidateEvaluationArtifacts: false
    )
}
