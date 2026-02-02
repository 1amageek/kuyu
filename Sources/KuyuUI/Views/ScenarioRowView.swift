import SwiftUI

struct ScenarioRowView: View {
    let scenario: ScenarioRunRecord

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scenario.id.scenarioId.rawValue)
                    .font(KuyuUITheme.titleFont(size: 13))
                    .foregroundStyle(KuyuUITheme.textPrimary)
                Text("Seed \(scenario.id.seed.rawValue)")
                    .font(KuyuUITheme.bodyFont(size: 11))
                    .foregroundStyle(KuyuUITheme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "Tilt %.1f°", scenario.metrics.maxTiltDegrees))
                Text(String(format: "Omega %.2f", scenario.metrics.maxOmega))
            }
            .font(KuyuUITheme.monoFont(size: 10))
            .foregroundStyle(KuyuUITheme.textSecondary)
            StatBadgeView(passed: scenario.evaluation.passed)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    ScenarioRowView(scenario: KuyuUIPreviewFactory.scenario())
        .padding()
        .background(KuyuUITheme.panelBackground)
}
