import SwiftUI

struct RunSummaryView: View {
    let run: RunRecord

    var body: some View {
        let determinism = run.scenarios.first?.log.determinism.tier.rawValue.uppercased() ?? "N/A"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Suite Result")
                    .font(KuyuUITheme.titleFont(size: 16))
                    .foregroundStyle(KuyuUITheme.textPrimary)
                Spacer()
                StatBadgeView(passed: run.output.summary.suitePassed)
            }
            HStack(spacing: 16) {
                Label("Scenarios: \(run.scenarios.count)", systemImage: "checklist")
                Label("Determinism: \(determinism)", systemImage: "speedometer")
            }
            .font(KuyuUITheme.bodyFont(size: 12))
            .foregroundStyle(KuyuUITheme.textSecondary)
        }
        .padding(12)
        .background(KuyuUITheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(KuyuUITheme.panelHighlight, lineWidth: 1)
        )
    }
}

#Preview {
    RunSummaryView(run: KuyuUIPreviewFactory.runRecord())
        .padding()
        .background(KuyuUITheme.background)
}
