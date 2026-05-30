import SwiftUI

public struct LogConsoleView: View {
    let entries: [UILogEntry]
    var filterText: String = ""
    let onClear: () -> Void
    @State private var search: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KuyuSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button {
                    onClear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .controlSize(.small)
                .help("Clear the log")
                .accessibilityLabel("Clear Log")
            }
            .padding(.horizontal, KuyuSpacing.sm)
            .padding(.vertical, KuyuSpacing.xs)

            Divider()

            MonospacedLogOutputView(
                lines: logLines,
                emptyMessage: "No logs yet",
                filterText: effectiveFilter
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The interactive search field takes precedence; otherwise the caller-supplied
    /// filter (if any) applies.
    private var effectiveFilter: String {
        search.isEmpty ? filterText : search
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
