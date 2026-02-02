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
            ScrollView {
                Text(entries.map { line(for: $0) }.joined(separator: "\n"))
                    .font(KuyuUITheme.monoFont(size: 11))
                    .foregroundStyle(KuyuUITheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .background(KuyuUITheme.panelBackground.opacity(0.85))
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
    LogConsoleView(entries: KuyuUIPreviewFactory.logEntries(), onClear: {})
        .background(KuyuUITheme.background)
}
