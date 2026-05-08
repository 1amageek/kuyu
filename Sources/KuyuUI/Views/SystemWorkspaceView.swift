import SwiftUI

struct SystemWorkspaceView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                HStack(alignment: .top, spacing: KuyuSpacing.md) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                            StatRow(label: "Local Runtime", value: "available")
                            StatRow(label: "Metal / MPS", value: "checked by MLX preflight")
                            StatRow(label: "Running Campaign", value: model.isLearningCampaignRunning ? "yes" : "no")
                            StatRow(label: "Artifact Monitor", value: model.learningCampaignMonitorEnabled ? "on" : "off")
                        }
                    } label: {
                        Label("Runtime", systemImage: "desktopcomputer")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                            StatRow(label: "Models", value: "\(model.availableModels.count)")
                            StatRow(label: "Runs", value: "\(model.runs.count)")
                            StatRow(label: "Logs", value: "\(model.logStore.entries.count)")
                            StatRow(label: "Cache", value: "managed externally")
                        }
                    } label: {
                        Label("Resources", systemImage: "shippingbox")
                    }
                }
            }
            .padding(KuyuSpacing.md)
        }
    }
}
