import Foundation
import Logging

public struct UILogHandler: LogHandler {
    public var metadata: Logger.Metadata = [:]
    public var logLevel: Logger.Level
    let label: String
    let buffer: UILogBuffer

    public init(label: String, level: Logger.Level = .info, buffer: UILogBuffer) {
        self.label = label
        self.logLevel = level
        self.buffer = buffer
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let timestamp = Date()
        var merged: [String: String] = [:]
        for (key, value) in self.metadata {
            merged[key] = value.description
        }
        if let metadata {
            for (key, value) in metadata {
                merged[key] = value.description
            }
        }

        let entry = UILogEntry(
            timestamp: timestamp,
            level: level,
            label: label,
            message: message.description,
            metadata: merged
        )
        Task {
            await buffer.append(entry)
        }
    }
}
