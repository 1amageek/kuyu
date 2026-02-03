import SwiftUI

struct LogConsoleView: View {
    let entries: [UILogEntry]
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Terminal")
                    .font(KuyuUITheme.titleFont(size: 14))
                    .foregroundStyle(KuyuUITheme.textPrimary)
                Spacer()
                Button("Clear", action: onClear)
                    .font(KuyuUITheme.bodyFont(size: 11))
            }
            if entries.isEmpty {
                Text("No logs yet")
                    .font(KuyuUITheme.bodyFont(size: 12))
                    .foregroundStyle(KuyuUITheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    Text(entries.map { line(for: $0) }.joined(separator: "\n"))
                        .font(KuyuUITheme.monoFont(size: 11))
                        .foregroundStyle(KuyuUITheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .background(KuyuUITheme.panelBackground.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .background(KuyuUITheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
