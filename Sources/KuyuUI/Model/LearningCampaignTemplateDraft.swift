import Foundation

struct LearningCampaignTemplateDraft: Sendable, Codable, Equatable {
    var name: String
    var description: String
    var tags: [String]
    var task: String
    var suites: String
    var seedCount: Int
    var population: Int
    var generations: Int
    var episodes: Int
    var strategy: String
    var preset: String
    var artifactRetention: String
    var createdAt: Date
}
