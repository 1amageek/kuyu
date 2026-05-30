import SwiftUI

struct KeyTrainingChartsView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            LazyVGrid(columns: metricColumns, spacing: KuyuSpacing.sm) {
                DashboardMetricCardView(
                    title: "Average Reward",
                    systemImage: "chart.line.uptrend.xyaxis",
                    value: formattedMetric(rewardSamples.last?.value, precision: 1),
                    delta: formattedDelta(rewardSamples),
                    samples: rewardSamples,
                    tint: .blue
                )

                DashboardMetricCardView(
                    title: "Generation",
                    systemImage: "number",
                    value: generationValue,
                    delta: generationDelta,
                    samples: generationSamples,
                    tint: .purple
                )

                DashboardMetricCardView(
                    title: "Population Diversity",
                    systemImage: "circle.grid.2x2",
                    value: formattedMetric(populationDiversity, precision: 3),
                    delta: formattedDelta(populationDiversitySamples, precision: 3),
                    samples: populationDiversitySamples,
                    tint: .cyan
                )

                DashboardMetricCardView(
                    title: "Best Fitness",
                    systemImage: "trophy",
                    value: formattedMetric(bestFitness, precision: 2),
                    delta: formattedMetricDelta(bestFitnessDelta, precision: 3),
                    samples: fitnessSamples,
                    tint: .mint
                )

                DashboardMetricCardView(
                    title: "Episodes",
                    systemImage: "play.rectangle",
                    value: formattedCount(liveEpisodeCount),
                    delta: episodeDelta,
                    samples: episodeSamples,
                    tint: .indigo
                )
            }

            HStack(alignment: .top, spacing: KuyuSpacing.md) {
                LearningMetricChartView(
                    title: "Reinforcement Learning",
                    subtitle: "Reward over time",
                    unit: "reward",
                    samples: rewardSamples,
                    tint: .blue,
                    trailingValue: rewardSamples.last?.value,
                    xAxisLabel: "generation"
                )
                LearningMetricChartView(
                    title: "Genetic Learning",
                    subtitle: "Population fitness over generations",
                    unit: "fitness",
                    samples: fitnessSamples,
                    tint: .purple,
                    trailingValue: fitnessSamples.last?.value,
                    xAxisLabel: "generation"
                )
            }

            HStack(alignment: .top, spacing: KuyuSpacing.md) {
                LearningMetricChartView(
                    title: "Task Pass",
                    subtitle: "Best candidate task pass rate",
                    unit: "0...1",
                    samples: taskPassSamples,
                    tint: .green,
                    trailingValue: taskPassSamples.last?.value,
                    xAxisLabel: "generation"
                )
                LearningMetricChartView(
                    title: "Hold / Altitude",
                    subtitle: "Hold ratio and altitude error proxy",
                    unit: "ratio",
                    samples: holdOrAltitudeSamples,
                    tint: .orange,
                    trailingValue: holdOrAltitudeSamples.last?.value,
                    xAxisLabel: "generation"
                )
            }
        }
    }

    private var metricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 132), spacing: KuyuSpacing.sm), count: 5)
    }

    private var rewardSamples: [MetricSample] {
        // Reward-average sources only. Loop score is a different metric and must not be
        // substituted under the "Reward" label; an empty result yields an empty state.
        if !model.learningCampaignLiveRewardSamples.isEmpty {
            return model.learningCampaignLiveRewardSamples
        }
        if let live = model.learningCampaignState?.liveRewardAverageSamples, !live.isEmpty {
            return live
        }
        return model.rewardAverageSamples
    }

    private var fitnessSamples: [MetricSample] {
        if !model.learningCampaignLiveFitnessSamples.isEmpty {
            return model.learningCampaignLiveFitnessSamples
        }
        return model.learningCampaignState?.liveBestFitnessSamples ?? []
    }

    private var generationSamples: [MetricSample] {
        // Real generation-count series only; no synthetic `time + 1` placeholder.
        model.learningCampaignState?.liveGenerationCountSamples ?? []
    }

    private var episodeSamples: [MetricSample] {
        if !model.learningCampaignLiveEpisodeSamples.isEmpty {
            return model.learningCampaignLiveEpisodeSamples
        }
        return model.learningCampaignState?.liveEpisodeSamples ?? []
    }

    private var populationDiversitySamples: [MetricSample] {
        model.learningCampaignState?.livePopulationDiversitySamples ?? []
    }

    private var populationDiversity: Double? {
        model.learningCampaignState?.populationDiversity
    }

    private var taskPassSamples: [MetricSample] {
        if !model.learningCampaignLiveTaskPassSamples.isEmpty {
            return model.learningCampaignLiveTaskPassSamples
        }
        return model.learningCampaignState?.liveTaskPassRateSamples ?? []
    }

    private var holdOrAltitudeSamples: [MetricSample] {
        if !model.learningCampaignLiveHoldTimeSamples.isEmpty {
            return model.learningCampaignLiveHoldTimeSamples
        }
        if !model.learningCampaignLiveAltitudeErrorSamples.isEmpty {
            return model.learningCampaignLiveAltitudeErrorSamples
        }
        if let hold = model.learningCampaignState?.liveHoldTimeRatioSamples, !hold.isEmpty {
            return hold
        }
        return model.learningCampaignState?.liveAltitudeErrorRatioSamples ?? []
    }

    private var bestFitness: Double? {
        if let live = fitnessSamples.map(\.value).max() {
            return live
        }
        return model.learningCampaignState?.bestFitness
    }

    private var bestFitnessDelta: Double? {
        guard let first = fitnessSamples.first?.value, let bestFitness else {
            return model.learningCampaignState?.bestFitnessDeltaFromInitial
        }
        return bestFitness - first
    }

    private var liveEpisodeCount: Int? {
        if let live = episodeSamples.last?.value {
            return Int(live)
        }
        return model.learningCampaignState?.liveEpisodeCount
    }

    private var generationValue: String {
        guard let state = model.learningCampaignState else { return "--" }
        let planned = state.plannedGenerationCount
        if planned > 0 {
            return "\(state.completedGenerationCount) / \(planned)"
        }
        return "\(state.completedGenerationCount)"
    }

    private var generationDelta: String? {
        guard let state = model.learningCampaignState, state.completedGenerationCount > 0 else { return nil }
        return "+ \(state.completedGenerationCount)"
    }

    private var episodeDelta: String? {
        guard let state = model.learningCampaignState, state.liveEpisodeCount > 0 else { return nil }
        return "+ \(formattedCount(state.liveEpisodeCount))"
    }

    private func formattedMetric(_ value: Double?, precision: Int) -> String {
        guard let value, value.isFinite else { return "--" }
        return String(format: "%.\(precision)f", value)
    }

    private func formattedCount(_ value: Int?) -> String {
        guard let value else { return "--" }
        return value.formatted()
    }

    private func formattedMetricDelta(_ value: Double?, precision: Int) -> String? {
        guard let value, value.isFinite else { return nil }
        let prefix = value >= 0 ? "+ " : "- "
        return "\(prefix)\(String(format: "%.\(precision)f", abs(value)))"
    }

    private func formattedDelta(_ samples: [MetricSample], precision: Int = 1) -> String? {
        guard let first = samples.first?.value, let last = samples.last?.value else { return nil }
        return formattedMetricDelta(last - first, precision: precision)
    }
}
