import SwiftUI

struct AnalysisInspectorView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                campaignStatistics
                sampleStatistics
            }
            .padding(KuyuSpacing.md)
        }
        .controlSize(.small)
    }

    private var campaignStatistics: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Status", value: model.learningCampaignState?.statusLabel ?? "--", compact: true)
                StatRow(
                    label: "Accepted",
                    value: model.learningCampaignState.map { "\($0.acceptedCount)/\($0.seedCount)" } ?? "--",
                    compact: true
                )
                StatRow(
                    label: "Best Delta",
                    value: model.learningCampaignState?.bestDelta.map { String(format: "%+.4f", $0) } ?? "--",
                    compact: true
                )
                StatRow(label: "Runs", value: "\(model.runs.count)", compact: true)
            }
        } label: {
            Label("Campaign", systemImage: "chart.bar.doc.horizontal")
        }
    }

    private var sampleStatistics: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Reward Samples", value: "\(model.learningCampaignRewardSamplesForDisplay.count)", compact: true)
                StatRow(label: "Loss Samples", value: "\(model.trainingLossSamples.count)", compact: true)
                StatRow(label: "Fitness Samples", value: "\(model.learningCampaignLiveFitnessSamples.count)", compact: true)
                StatRow(label: "Pass Rate Samples", value: "\(model.learningCampaignTaskPassSamplesForDisplay.count)", compact: true)
            }
        } label: {
            Label("Samples", systemImage: "square.stack.3d.up")
        }
    }
}
