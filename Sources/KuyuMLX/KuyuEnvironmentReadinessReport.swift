import Foundation

public struct KuyuEnvironmentReadinessReport: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public let reportID: String
    public let generatedAt: Date
    public let allReady: Bool
    public let tasks: [KuyuEnvironmentTaskReadiness]

    public init(
        schemaVersion: Int = 1,
        reportID: String = "environment-readiness-\(UUID().uuidString)",
        generatedAt: Date = Date(),
        tasks: [KuyuEnvironmentTaskReadiness]
    ) {
        self.schemaVersion = schemaVersion
        self.reportID = reportID
        self.generatedAt = generatedAt
        self.allReady = tasks.allSatisfy(\.ready)
        self.tasks = tasks
    }
}
