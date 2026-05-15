import SwiftUI

struct BoundedRunStatusChipsView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        HStack(spacing: KuyuSpacing.sm) {
            StatusPill(statusLabel, tone: statusTone)
            chip("世代/上限", generationValue)
            chip("エピソード", episodeValue)
            chip("平均報酬", rewardValue)
            chip("最良適応度", fitnessValue)
            StatusPill("接続済み", tone: .success)
        }
        .font(.caption)
        .lineLimit(1)
    }

    private func chip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, KuyuSpacing.sm)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.20))
        .clipShape(Capsule())
    }

    private var statusLabel: String {
        if model.isLearningCampaignRunning { return "実行中" }
        return model.learningCampaignState?.statusLabel ?? "待機中"
    }

    private var statusTone: StatusPill.Tone {
        if model.isLearningCampaignRunning { return .success }
        switch statusLabel.lowercased() {
        case "failed", "invalid": return .danger
        case "cancelled": return .warning
        case "succeeded", "completed", "valid": return .success
        default: return .neutral
        }
    }

    private var generationValue: String {
        guard let state = model.learningCampaignState else { return "--" }
        let latest = state.latestGenerations.first?.generationIndex ?? -1
        let total = state.plan?.generations ?? model.learningCampaignGenerations
        return "\(max(0, latest + 1)) / \(total)"
    }

    private var episodeValue: String {
        let state = model.learningCampaignState
        let seedCount = state?.seedCount ?? model.learningCampaignSeedCount
        let generations = state?.plan?.generations ?? model.learningCampaignGenerations
        let population = state?.plan?.population ?? model.learningCampaignPopulation
        let episodesPerCandidate = state?.plan?.episodes ?? model.learningCampaignEpisodes
        let episodes = seedCount * generations * population * episodesPerCandidate
        return episodes.formatted()
    }

    private var rewardValue: String {
        guard let reward = model.rewardAverageSamples.last?.value ?? model.loopScoreSamples.last?.value else {
            return "--"
        }
        return String(format: "%.1f", reward)
    }

    private var fitnessValue: String {
        guard let best = model.learningCampaignState?.generations.compactMap(\.bestFitness).max() else {
            return "--"
        }
        return String(format: "%.1f", best)
    }
}
