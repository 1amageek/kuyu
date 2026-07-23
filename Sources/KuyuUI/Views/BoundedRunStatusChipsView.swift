import SwiftUI

struct BoundedRunStatusChipsView: View {
  @Bindable var model: SimulationViewModel

  var body: some View {
    HStack(spacing: KuyuSpacing.sm) {
      if isBusy {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel("Running")
      }
      StatusPill(statusLabel, tone: statusTone)
      chip("Gen/Max", generationValue)
      chip("Episodes", episodeValue)
      chip("Avg Reward", rewardValue)
      chip("Best Fitness", fitnessValue)
      StatusPill("Connected", tone: .success)
    }
    .font(.caption)
    .lineLimit(1)
  }

  private var isBusy: Bool {
    model.isLearningCampaignRunning || model.isRunning
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
    if isBusy { return "Running" }
    return model.learningCampaignState?.statusLabel ?? "Idle"
  }

  private var statusTone: StatusPill.Tone {
    if isBusy { return .info }
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
    let searchEpisodes = state?.plan?.searchEpisodes ?? model.learningCampaignEpisodes
    let searchSuiteCount = state?.plan?.searchSuites.count ?? 1
    let episodes = seedCount * generations * population * searchEpisodes * max(1, searchSuiteCount)
    return episodes.formatted()
  }

  private var rewardValue: String {
    guard let reward = model.learningCampaignRewardSamplesForDisplay.last?.value else {
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
