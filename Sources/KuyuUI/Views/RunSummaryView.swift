import Foundation
import SwiftUI

public struct RunSummaryView: View {
    let run: RunRecord

    public var body: some View {
        let determinism = run.scenarios.first?.log.determinism.tier.rawValue.uppercased() ?? "N/A"
        let aggregate = run.output.summary.aggregate
        let recoveryText = aggregate.averageRecoveryTime.map { String(format: "%.2fs", $0) } ?? "n/a"
        let overshootText = aggregate.worstOvershootDegrees.map { String(format: "%.2f", $0) } ?? "n/a"
        let hfText = aggregate.averageHfStabilityScore.map { String(format: "%.2f", $0) } ?? "n/a"
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

            HStack(spacing: 16) {
                Label("Avg Recovery: \(recoveryText)", systemImage: "waveform.path.ecg")
                Label("Worst Overshoot: \(overshootText)", systemImage: "arrow.up.right")
                Label("Avg HF: \(hfText)", systemImage: "waveform.path")
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
