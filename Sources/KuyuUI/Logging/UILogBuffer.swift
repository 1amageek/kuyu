import Foundation

public actor UILogBuffer {
    private let maximumEntryCount: Int
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private var entries: [UILogEntry] = []
    private var continuations: [UUID: AsyncStream<UILogEntry>.Continuation] = [:]

    public init(maximumEntryCount: Int = 2_000) {
        self.maximumEntryCount = max(1, maximumEntryCount)
    }

    public func append(_ entry: UILogEntry) {
        insertEntryInTimestampOrder(entry)
        trimEntriesIfNeeded()
        for continuation in continuations.values {
            continuation.yield(entry)
        }
        print(format(entry))
    }

    public func stream() -> AsyncStream<UILogEntry> {
        let streamID = UUID()
        return AsyncStream { continuation in
            self.continuations[streamID] = continuation
            continuation.onTermination = { _ in
                Task {
                    await self.clearContinuation(id: streamID)
                }
            }
            for entry in entries {
                continuation.yield(entry)
            }
        }
    }

    public func clear() {
        entries.removeAll()
    }

    public func shutdown() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        entries.removeAll(keepingCapacity: false)
    }

    private func clearContinuation(id: UUID) {
        continuations[id] = nil
    }

    private func trimEntriesIfNeeded() {
        guard entries.count > maximumEntryCount else {
            return
        }
        entries.removeFirst(entries.count - maximumEntryCount)
    }

    private func insertEntryInTimestampOrder(_ entry: UILogEntry) {
        guard let last = entries.last, last.timestamp > entry.timestamp else {
            entries.append(entry)
            return
        }
        let index = entries.firstIndex { $0.timestamp > entry.timestamp } ?? entries.endIndex
        entries.insert(entry, at: index)
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
