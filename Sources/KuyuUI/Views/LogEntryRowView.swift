import Logging
import SwiftUI

struct LogEntryRowView: View {
    let entry: UILogEntry

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.formatter.string(from: entry.timestamp))
                .font(KuyuUITheme.monoFont(size: 10))
                .foregroundStyle(KuyuUITheme.textSecondary)
                .frame(width: 72, alignment: .leading)
            Text(entry.level.rawValue.uppercased())
                .font(KuyuUITheme.monoFont(size: 10))
                .foregroundStyle(levelColor(entry.level))
                .frame(width: 54, alignment: .leading)
            Text(entry.label)
                .font(KuyuUITheme.monoFont(size: 10))
                .foregroundStyle(KuyuUITheme.textSecondary)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(KuyuUITheme.bodyFont(size: 11))
                    .foregroundStyle(KuyuUITheme.textPrimary)
                if !entry.metadata.isEmpty {
                    Text(entry.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                        .font(KuyuUITheme.monoFont(size: 9))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func levelColor(_ level: Logger.Level) -> Color {
        switch level {
        case .trace, .debug:
            return KuyuUITheme.textSecondary
        case .info, .notice:
            return KuyuUITheme.accent
        case .warning:
            return KuyuUITheme.warning
        case .error, .critical:
            return Color.red
        }
    }
}

#Preview {
    LogEntryRowView(entry: KuyuUIPreviewFactory.logEntries().first!)
        .padding()
        .background(KuyuUITheme.background)
}
