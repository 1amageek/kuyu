import SwiftUI

struct ReinforcementLearningConfigView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    StatRow(label: "Algorithm", value: "Backend Protocol")
                    IntegerStepperView(label: "Epochs", value: $model.trainingEpochs, range: 1...100)
                    IntegerStepperView(label: "Sequence Length", value: $model.trainingSequenceLength, range: 4...128)
                    DoubleSliderView(
                        label: "Learning Rate",
                        value: $model.trainingLearningRate,
                        range: 0.00001...0.01,
                        display: String(format: "%.5f", model.trainingLearningRate)
                    )
                    Toggle("Auxiliary Loss", isOn: $model.trainingUseAux)
                    TextField("Training Dataset", text: $model.trainingInputDirectory)
                        .textFieldStyle(.roundedBorder)
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
