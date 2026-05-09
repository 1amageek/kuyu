import Foundation
import Observation

@Observable
@MainActor
public final class UILogStore {
    private let maximumEntryCount: Int
    private(set) var entries: [UILogEntry] = []
    private let buffer: UILogBuffer
    private var streamTask: Task<Void, Never>?
    private var entryObserver: ((UILogEntry) -> Void)?

    public init(buffer: UILogBuffer, maximumEntryCount: Int = 2_000) {
        self.buffer = buffer
        self.maximumEntryCount = max(1, maximumEntryCount)
        startStreaming()
    }

    public func clear() {
        entries.removeAll()
        Task {
            await buffer.clear()
        }
    }

    public func append(_ entry: UILogEntry) {
        emit(entry)
    }

    public func emit(_ entry: UILogEntry) {
        Task {
            await buffer.append(entry)
        }
    }

    public func setEntryObserver(_ observer: @escaping (UILogEntry) -> Void) {
        entryObserver = observer
    }

    private func startStreaming() {
        streamTask?.cancel()
        streamTask = Task { [buffer] in
            let stream = await buffer.stream()
            for await entry in stream {
                appendLocal(entry)
            }
        }
    }

    public func shutdown() {
        streamTask?.cancel()
        streamTask = nil
        entryObserver = nil
        entries.removeAll(keepingCapacity: false)
        Task {
            await buffer.shutdown()
        }
    }

    public func shutdownAndWait() async {
        streamTask?.cancel()
        streamTask = nil
        entryObserver = nil
        entries.removeAll(keepingCapacity: false)
        await buffer.shutdown()
    }

    private func appendLocal(_ entry: UILogEntry) {
        insertEntryInTimestampOrder(entry)
        if entries.count > maximumEntryCount {
            entries.removeFirst(entries.count - maximumEntryCount)
        }
        entryObserver?(entry)
    }

    private func insertEntryInTimestampOrder(_ entry: UILogEntry) {
        guard let last = entries.last, last.timestamp > entry.timestamp else {
            entries.append(entry)
            return
        }
        let index = entries.firstIndex { $0.timestamp > entry.timestamp } ?? entries.endIndex
        entries.insert(entry, at: index)
    }

}
