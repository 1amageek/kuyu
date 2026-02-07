import Logging
import SwiftUI

public struct LogEntryRowView: View {
    let entry: UILogEntry

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.formatter.string(from: entry.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(entry.level.rawValue.uppercased())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(levelColor(entry.level))
                .frame(width: 54, alignment: .leading)
            Text(entry.label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                if !entry.metadata.isEmpty {
                    Text(entry.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func levelColor(_ level: Logger.Level) -> Color {
        switch level {
        case .trace, .debug:
            return Color.secondary
        case .info, .notice:
            return Color.accentColor
        case .warning:
            return Color.orange
        case .error, .critical:
            return Color.red
        }
    }
}

#Preview {
    LogEntryRowView(entry: KuyuUIPreviewFactory.logEntries(output: KuyuUIPreviewFactory.runRecord().output).first!)
        .padding()
}
