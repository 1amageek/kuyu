import Foundation
import Logging

public struct UILogEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    let timestamp: Date
    let level: Logger.Level
    let label: String
    let message: String
    let metadata: [String: String]

    public init(timestamp: Date, level: Logger.Level, label: String, message: String, metadata: [String: String]) {
        self.id = UUID()
        self.timestamp = timestamp
        self.level = level
        self.label = label
        self.message = message
        self.metadata = metadata
    }
}
