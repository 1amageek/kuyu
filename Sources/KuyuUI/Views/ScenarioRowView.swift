import SwiftUI

public struct ScenarioRowView: View {
    let scenario: ScenarioRunRecord

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scenario.id.scenarioId.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text("Seed \(scenario.id.seed.rawValue)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "Tilt %.1f°", scenario.metrics.maxTiltDegrees))
                Text(String(format: "Omega %.2f", scenario.metrics.maxOmega))
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            StatBadgeView(passed: scenario.evaluation.passed)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    if let scenario = KuyuUIPreviewFactory.scenario() {
        ScenarioRowView(scenario: scenario)
            .padding()
    } else {
        Text("Preview unavailable")
            .padding()
    }
}
