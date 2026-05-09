import SwiftUI

struct LogSummaryView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            if model.logStore.entries.isEmpty {
                Text("No log entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                CopyableTextBlockView(
                    title: "Recent Log Copy",
                    text: recentLogText,
                    emptyText: "No log entries"
                )
                ForEach(model.logStore.entries.suffix(30)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentLogText: String {
        model.logStore.entries
            .suffix(30)
            .map { entry in
                "\(entry.timestamp.formatted(date: .numeric, time: .standard)) \(entry.level.rawValue) \(entry.message)"
            }
            .joined(separator: "\n")
    }
}
