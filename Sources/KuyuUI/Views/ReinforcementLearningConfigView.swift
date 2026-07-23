import SwiftUI

struct ReinforcementLearningConfigView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    StatRow(label: "Algorithm", value: "Backend Protocol")
                    IntegerStepperView(label: "Episodes", value: $model.learningCampaignEpisodes, range: 1...100)
                    Toggle("Auxiliary Loss", isOn: $model.trainingUseAux)
                    Toggle("Quality Gating", isOn: $model.trainingUseQualityGating)
                    Toggle("Require Initial Parent Pass", isOn: $model.learningCampaignRequiresInitialParentPass)
                }
            } label: {
                Label("Reinforcement Learning", systemImage: "flask")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    StatRow(label: "Policy Network", value: "Manas Core")
                    StatRow(label: "Value Network", value: "backend-owned")
                    StatRow(label: "Optimizer", value: "Manas/MLX")
                    StatRow(label: "Reward Shaping", value: "task profile")
                }
            } label: {
                Label("Architecture", systemImage: "square.stack.3d.up")
            }
        }
    }
}
