import SwiftUI

struct RunRowView: View {
    let run: RunRecord

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.formatter.string(from: run.timestamp))
                    .font(KuyuUITheme.bodyFont(size: 12))
                    .foregroundStyle(KuyuUITheme.textPrimary)
                Spacer()
                StatBadgeView(passed: run.output.summary.suitePassed)
            }
            Text("Scenarios: \(run.scenarios.count)")
                .font(KuyuUITheme.bodyFont(size: 11))
                .foregroundStyle(KuyuUITheme.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RunRowView(run: KuyuUIPreviewFactory.runRecord())
        .frame(width: 260)
        .padding()
        .background(KuyuUITheme.panelBackground)
}
