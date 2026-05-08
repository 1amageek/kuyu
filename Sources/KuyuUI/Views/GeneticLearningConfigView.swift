import SwiftUI

struct GeneticLearningConfigView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    IntegerStepperView(label: "Population Size", value: $model.learningCampaignPopulation, range: 1...512)
                    IntegerStepperView(label: "Elite Retention", value: $model.learningCampaignEliteCount, range: 1...64)
                    IntegerStepperView(label: "Generation Limit", value: $model.learningCampaignGenerations, range: 1...10_000)
                    DoubleSliderView(
                        label: "Mutation Rate",
                        value: $model.learningCampaignMutationRate,
                        range: 0...1,
                        display: String(format: "%.3f", model.learningCampaignMutationRate)
                    )
                    DoubleSliderView(
                        label: "Mutation Noise",
                        value: $model.learningCampaignMutationNoiseScale,
                        range: 0...0.25,
                        display: String(format: "%.4f", model.learningCampaignMutationNoiseScale)
                    )
                    DoubleSliderView(
                        label: "Diversity Threshold",
                        value: $model.learningCampaignMinimumIncumbentImprovement,
                        range: 0...1,
                        display: String(format: "%.3f", model.learningCampaignMinimumIncumbentImprovement)
                    )
                    Toggle("Adaptive Mutation", isOn: $model.learningCampaignAdaptiveMutation)
                }
            } label: {
                Label("Genetic Learning", systemImage: "point.3.connected.trianglepath.dotted")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    StatRow(label: "Selection Strategy", value: "quality diversity")
                    StatRow(label: "Variation", value: "gaussian")
                    StatRow(label: "Fitness Function", value: "task quality gate")
                    StatRow(label: "Early Stopping", value: "acceptance gate")
                }
            } label: {
                Label("Strategy", systemImage: "list.bullet.rectangle")
            }
        }
    }
}
