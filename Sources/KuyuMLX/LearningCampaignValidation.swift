import Foundation

public struct LearningCampaignValidation: Codable, Sendable, Equatable {
    public let timestamp: String
    public let artifactRoot: String
    public let valid: Bool
    public let issueCount: Int
    public let issues: [LearningCampaignValidationIssue]
}
