import Foundation

struct ReportExportPayload: Codable, Sendable, Equatable {
    let generatedAt: Date
    let project: String
    let task: String
    let campaignStatus: String?
    let readiness: String
    let acceptedCount: Int?
    let seedCount: Int?
    let bestDelta: Double?
    let finalCheckpoint: String?
    let rewardSampleCount: Int
    let runCount: Int
    let logCount: Int
}
