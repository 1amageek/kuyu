import SwiftUI

struct LearningStudioHeaderView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        HStack(spacing: KuyuSpacing.md) {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                Text("Kuyu Learning Studio")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("Manas checkpoint evolution, regression gate, and simulation quality")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            StatusPill(model.isLearningCampaignRunning ? "running" : statusLabel, tone: statusTone)

            HeaderMetricView(
                label: "Phase",
                value: model.learningCampaignCurrentPhase
            )
            HeaderMetricView(
                label: "Generation",
                value: generationValue
            )
            HeaderMetricView(
                label: "Accepted",
                value: acceptedValue
            )
            HeaderMetricView(
                label: "Progress",
                value: String(format: "%.0f%%", model.learningCampaignProgressFraction * 100)
            )
        }
        .padding(.horizontal, KuyuSpacing.md)
        .padding(.vertical, KuyuSpacing.sm)
        .background(.quaternary.opacity(0.5))
        .overlay {
            RoundedRectangle(cornerRadius: KuyuRadius.large, style: .continuous)
                .stroke(.separator, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: KuyuRadius.large, style: .continuous))
    }

    private var statusLabel: String {
        model.learningCampaignState?.statusLabel ?? "idle"
    }

    private var statusTone: StatusPill.Tone {
        if model.isLearningCampaignRunning { return .success }
        switch statusLabel.lowercased() {
        case "succeeded", "completed", "valid":
            return .success
        case "failed", "invalid":
            return .danger
        case "cancelled":
            return .warning
        case "running", "started":
            return .info
        default:
            return .neutral
        }
    }

    private var generationValue: String {
        guard let state = model.learningCampaignState else { return "--" }
        let latest = state.latestGenerations.first?.generationIndex
        let total = state.plan?.generations
        switch (latest, total) {
        case let (.some(latest), .some(total)):
            return "\(latest + 1) / \(total)"
        case let (.some(latest), .none):
            return "\(latest + 1)"
        case let (.none, .some(total)):
            return "0 / \(total)"
        case (.none, .none):
            return "--"
        }
    }

    private var acceptedValue: String {
        guard let state = model.learningCampaignState else { return "--" }
        return "\(state.acceptedCount) / \(state.seedCount)"
    }
}
