import Foundation

public struct LearningCampaignValidation: Codable, Sendable, Equatable {
    public let timestamp: String
    public let artifactRoot: String
    public let valid: Bool
    public let issueCount: Int
    public let issues: [LearningCampaignValidationIssue]

    public init(
        timestamp: String,
        artifactRoot: String,
        valid: Bool,
        issueCount: Int,
        issues: [LearningCampaignValidationIssue]
    ) {
        self.timestamp = timestamp
        self.artifactRoot = artifactRoot
        self.valid = valid
        self.issueCount = issueCount
        self.issues = issues
    }
}
