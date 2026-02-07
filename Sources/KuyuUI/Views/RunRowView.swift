import SwiftUI

public struct RunRowView: View {
    let run: RunRecord

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.formatter.string(from: run.timestamp))
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                StatBadgeView(passed: run.output.summary.suitePassed)
            }
            Text("Scenarios: \(run.scenarios.count)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RunRowView(run: KuyuUIPreviewFactory.runRecord())
        .frame(width: 260)
        .padding()
}
