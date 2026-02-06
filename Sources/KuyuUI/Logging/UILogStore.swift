import Foundation
import Observation

@Observable
@MainActor
public final class UILogStore {
    private(set) var entries: [UILogEntry] = []
    private let buffer: UILogBuffer
    private var streamTask: Task<Void, Never>?
    private var entryObserver: ((UILogEntry) -> Void)?

    public init(buffer: UILogBuffer) {
        self.buffer = buffer
        startStreaming()
    }

    public func clear() {
        entries.removeAll()
        Task {
            await buffer.clear()
        }
    }

    public func append(_ entry: UILogEntry) {
        entries.append(entry)
        Task {
            await buffer.append(entry)
        }
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
                await MainActor.run {
                    self.entries.append(entry)
                    self.entryObserver?(entry)
                }
            }
        }
    }

    deinit {}
}
