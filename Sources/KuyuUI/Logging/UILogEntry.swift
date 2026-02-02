import Foundation
import Logging

struct UILogEntry: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let level: Logger.Level
    let label: String
    let message: String
    let metadata: [String: String]

    init(timestamp: Date, level: Logger.Level, label: String, message: String, metadata: [String: String]) {
        self.id = UUID()
        self.timestamp = timestamp
        self.level = level
        self.label = label
        self.message = message
        self.metadata = metadata
    }
}
