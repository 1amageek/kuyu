import Foundation

public struct LearningCampaignStatus: Codable, Sendable, Equatable {
    public let status: String
    public let exitCode: Int
    public let startedAt: String
    public let finishedAt: String

    public init(status: String, exitCode: Int, startedAt: String, finishedAt: String) {
        self.status = status
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
