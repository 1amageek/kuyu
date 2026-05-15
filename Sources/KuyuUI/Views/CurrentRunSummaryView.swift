import SwiftUI

struct CurrentRunSummaryView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: KuyuSpacing.lg, verticalSpacing: KuyuSpacing.sm) {
                GridRow {
                    summaryItem("Status", status)
                    summaryItem("Generation / Budget", generation)
                    summaryItem("Episode", episode)
                    summaryItem("Reward", reward)
                    summaryItem("Fitness", fitness)
                    summaryItem("Current Phase", model.learningCampaignCurrentPhase)
                    summaryItem("Last Checkpoint", checkpoint)
                }
            }
        } label: {
            Label("Current Run", systemImage: "gauge.with.dots.needle.67percent")
        }
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var status: String {
        if model.isLearningCampaignRunning { return "running" }
        return model.learningCampaignState?.statusLabel ?? "idle"
    }

    private var generation: String {
        guard let state = model.learningCampaignState else { return "--" }
        let latest = state.latestGenerations.first?.generationIndex ?? -1
        return "\(max(0, latest + 1)) / \(state.plan?.generations ?? model.learningCampaignGenerations)"
    }

    private var episode: String {
        let state = model.learningCampaignState
        let seedCount = state?.seedCount ?? model.learningCampaignSeedCount
        let generations = state?.plan?.generations ?? model.learningCampaignGenerations
        let population = state?.plan?.population ?? model.learningCampaignPopulation
        let episodes = state?.plan?.episodes ?? model.learningCampaignEpisodes
        return (seedCount * generations * population * episodes).formatted()
    }

    private var reward: String {
        guard let value = model.rewardAverageSamples.last?.value ?? model.loopScoreSamples.last?.value else {
            return "--"
        }
        return String(format: "%.2f", value)
    }

    private var fitness: String {
        guard let value = model.learningCampaignState?.generations.compactMap(\.bestFitness).max() else {
            return "--"
        }
        return String(format: "%.2f", value)
    }

    private var checkpoint: String {
        guard let path = model.learningCampaignState?.finalCheckpoint else { return "--" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
