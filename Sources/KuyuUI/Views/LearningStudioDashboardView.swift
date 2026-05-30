import KuyuCore
import KuyuPhysics
import SwiftUI

struct LearningStudioDashboardView: View {
    @Bindable var model: SimulationViewModel
    let roll: Double
    let pitch: Double
    let yaw: Double
    let position: Axis3
    let renderInfo: RenderAssetInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                LearningStudioHeaderView(model: model)

                HStack(alignment: .top, spacing: KuyuSpacing.md) {
                    VStack(spacing: KuyuSpacing.md) {
                        HStack(alignment: .top, spacing: KuyuSpacing.md) {
                            LearningMetricChartView(
                                title: "Reinforcement Learning",
                                subtitle: "Reward over time",
                                unit: "reward",
                                samples: rewardSamples,
                                tint: .blue,
                                trailingValue: lastValue(rewardSamples)
                            )
                            EvolutionFitnessChartView(state: model.learningCampaignState)
                        }

                        HStack(alignment: .top, spacing: KuyuSpacing.md) {
                            PolicyLineageGraphView(state: model.learningCampaignState)
                            KuyuSimulationPreviewView(
                                model: model,
                                roll: roll,
                                pitch: pitch,
                                yaw: yaw,
                                position: position,
                                renderInfo: renderInfo
                            )
                        }

                        LearningExperimentListView(model: model)
                    }
                    .frame(maxWidth: .infinity)

                    LearningHyperparameterSettingsView(model: model)
                        .frame(width: 290)
                }
            }
            .padding(KuyuSpacing.md)
        }
    }

    private var rewardSamples: [MetricSample] {
        // "Reward over time" plots reward average only; loop score is a separate metric
        // and is not substituted here (empty → the chart shows its own empty state).
        model.rewardAverageSamples
    }

    private func lastValue(_ samples: [MetricSample]) -> Double? {
        samples.last?.value
    }
}
