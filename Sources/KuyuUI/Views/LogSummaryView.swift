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
                ForEach(model.logStore.entries.suffix(30)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                        Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
