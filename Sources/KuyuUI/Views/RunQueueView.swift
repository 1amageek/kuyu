import SwiftUI

struct RunQueueView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                queueRow("Current Campaign", value: model.isLearningCampaignRunning ? "running" : "idle", tone: model.isLearningCampaignRunning ? .success : .neutral)
                queueRow("Monitor", value: model.learningCampaignMonitorEnabled ? "watching" : "off", tone: model.learningCampaignMonitorEnabled ? .info : .neutral)
                queueRow("Candidate Concurrency", value: "\(model.learningCampaignCandidateEvaluationConcurrency)", tone: .neutral)
                queueRow("Workers", value: "\(model.learningCampaignWorkers)", tone: .neutral)
            }
        } label: {
            Label("Run Queue", systemImage: "tray.full")
        }
    }

    private func queueRow(_ label: String, value: String, tone: StatusPill.Tone) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            StatusPill(value, tone: tone)
        }
        .font(.caption)
    }
}
