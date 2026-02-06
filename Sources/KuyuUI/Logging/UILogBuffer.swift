import Foundation

public actor UILogBuffer {
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private var entries: [UILogEntry] = []
    private var continuation: AsyncStream<UILogEntry>.Continuation?

    public func append(_ entry: UILogEntry) {
        entries.append(entry)
        continuation?.yield(entry)
        print(format(entry))
    }

    public func stream() -> AsyncStream<UILogEntry> {
        AsyncStream { continuation in
            self.continuation = continuation
            for entry in entries {
                continuation.yield(entry)
            }
        }
    }

    public func clear() {
        entries.removeAll()
    }

    private func format(_ entry: UILogEntry) -> String {
        let timestamp = dateFormatter.string(from: entry.timestamp)
        let metadata = entry.metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        if metadata.isEmpty {
            return "\(timestamp) \(entry.level) \(entry.label) \(entry.message)"
        }
        return "\(timestamp) \(entry.level) \(entry.label) \(entry.message) \(metadata)"
    }
}
