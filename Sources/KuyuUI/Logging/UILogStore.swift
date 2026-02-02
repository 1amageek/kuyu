import Foundation
import Observation

@Observable
@MainActor
final class UILogStore {
    private(set) var entries: [UILogEntry] = []
    private let buffer: UILogBuffer
    private var streamTask: Task<Void, Never>?

    init(buffer: UILogBuffer) {
        self.buffer = buffer
        startStreaming()
    }

    func clear() {
        entries.removeAll()
        Task {
            await buffer.clear()
        }
    }

    func append(_ entry: UILogEntry) {
        entries.append(entry)
        Task {
            await buffer.append(entry)
        }
    }

    func emit(_ entry: UILogEntry) {
        Task {
            await buffer.append(entry)
        }
    }

    private func startStreaming() {
        streamTask?.cancel()
        streamTask = Task { [buffer] in
            let stream = await buffer.stream()
            for await entry in stream {
                await MainActor.run {
                    self.entries.append(entry)
                }
            }
        }
    }

    deinit {}
}
