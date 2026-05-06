import Foundation

public struct LearningCampaignStatus: Codable, Sendable, Equatable {
    public let status: String
    public let exitCode: Int
    public let startedAt: String
    public let finishedAt: String
}
