import Foundation
import Logging
import Testing
@testable import KuyuUI

@MainActor
@Test(.timeLimit(.minutes(1))) func uiLogStoreKeepsBoundedTimestampOrderedEntries() async throws {
    let store = UILogStore(buffer: UILogBuffer(maximumEntryCount: 3), maximumEntryCount: 3)

    let base = Date(timeIntervalSince1970: 1_000)
    store.append(makeUILogEntry(timestamp: base.addingTimeInterval(2), message: "third"))
    store.append(makeUILogEntry(timestamp: base, message: "first"))
    store.append(makeUILogEntry(timestamp: base.addingTimeInterval(1), message: "second"))
    store.append(makeUILogEntry(timestamp: base.addingTimeInterval(3), message: "fourth"))

    let entries = try await waitForUILogEntries(store: store, count: 3, latestMessage: "fourth")
    #expect(entries.map(\.message) == ["second", "third", "fourth"])
    await store.shutdownAwaitingCompletion()
}

@MainActor
private func waitForUILogEntries(store: UILogStore, count: Int, latestMessage: String) async throws -> [UILogEntry] {
    for _ in 0..<40 {
        if store.entries.count == count, store.entries.last?.message == latestMessage {
            return store.entries
        }
        try await Task.sleep(for: .milliseconds(25))
    }
    return store.entries
}

private func makeUILogEntry(timestamp: Date, message: String) -> UILogEntry {
    UILogEntry(
        timestamp: timestamp,
        level: .info,
        label: "kuyu.ui",
        message: message,
        metadata: [:]
    )
}
