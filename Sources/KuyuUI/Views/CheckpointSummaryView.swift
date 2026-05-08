import SwiftUI

struct CheckpointSummaryView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Final", value: finalCheckpoint, compact: true)
                StatRow(label: "Accepted", value: accepted, compact: true)
                StatRow(label: "Validation", value: model.learningCampaignState?.validationLabel ?? "--", compact: true)
                StatRow(label: "Source", value: sourceCheckpoint, compact: true)
            }
        } label: {
            Label("Checkpoint Summary", systemImage: "checkmark.seal")
        }
    }

    private var finalCheckpoint: String {
        guard let value = model.learningCampaignState?.finalCheckpoint else { return "--" }
        return URL(fileURLWithPath: value).lastPathComponent
    }

    private var accepted: String {
        guard let state = model.learningCampaignState else { return "--" }
        return "\(state.acceptedCount) / \(state.seedCount)"
    }

    private var sourceCheckpoint: String {
        let path = model.learningCampaignSourceCheckpointPath
        guard !path.isEmpty else { return "--" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
