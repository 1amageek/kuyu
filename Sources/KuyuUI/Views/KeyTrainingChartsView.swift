import SwiftUI

struct KeyTrainingChartsView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        HStack(alignment: .top, spacing: KuyuSpacing.md) {
            LearningMetricChartView(
                title: "Reward",
                subtitle: "Reward over time",
                unit: "reward",
                samples: rewardSamples,
                tint: .blue,
                trailingValue: rewardSamples.last?.value
            )
            EvolutionFitnessChartView(state: model.learningCampaignState)
        }
    }

    private var rewardSamples: [MetricSample] {
        if !model.rewardAverageSamples.isEmpty {
            return model.rewardAverageSamples
        }
        return model.loopScoreSamples
    }
}
