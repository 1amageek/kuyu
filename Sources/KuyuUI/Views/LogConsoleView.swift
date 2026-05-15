import SwiftUI

public struct LogConsoleView: View {
    let entries: [UILogEntry]
    var filterText: String = ""
    let onClear: () -> Void

    public var body: some View {
        MonospacedLogOutputView(
            lines: logLines,
            emptyMessage: "No logs yet",
            filterText: filterText
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logLines: [MonospacedLogLine] {
        entries.map { entry in
            MonospacedLogLine(id: entry.id.uuidString, text: line(for: entry))
        }
    }

    private func line(for entry: UILogEntry) -> String {
        let time = LogEntryRowView.formatter.string(from: entry.timestamp)
        let level = entry.level.rawValue.uppercased()
        let label = entry.label
        let message = entry.message
        let metadata = entry.metadata.isEmpty
            ? ""
            : " " + entry.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        return "\(time) \(level) \(label) \(message)\(metadata)"
    }
}

#Preview {
    LogConsoleView(entries: KuyuUIPreviewFactory.logEntries(output: KuyuUIPreviewFactory.runRecord().output), onClear: {})
}
