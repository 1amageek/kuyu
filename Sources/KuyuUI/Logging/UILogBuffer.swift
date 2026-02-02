actor UILogBuffer {
    private var entries: [UILogEntry] = []
    private var continuation: AsyncStream<UILogEntry>.Continuation?

    func append(_ entry: UILogEntry) {
        entries.append(entry)
        continuation?.yield(entry)
    }

    func stream() -> AsyncStream<UILogEntry> {
        AsyncStream { continuation in
            self.continuation = continuation
            for entry in entries {
                continuation.yield(entry)
            }
        }
    }

    func clear() {
        entries.removeAll()
    }
}
