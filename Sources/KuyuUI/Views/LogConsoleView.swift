import SwiftUI

public struct LogConsoleView: View {
    let entries: [UILogEntry]
    let onClear: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                if entries.isEmpty {
                    Text("No logs yet")
                        .font(KuyuUITheme.bodyFont(size: 12))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    Text(entries.map { line(for: $0) }.joined(separator: "\n"))
                        .font(KuyuUITheme.monoFont(size: 11))
                        .foregroundStyle(KuyuUITheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .background(KuyuUITheme.background)
}
