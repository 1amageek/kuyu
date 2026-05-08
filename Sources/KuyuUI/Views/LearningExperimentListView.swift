import SwiftUI

struct LearningExperimentListView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: KuyuSpacing.md, verticalSpacing: KuyuSpacing.sm) {
                headerRow
                Divider()
                ForEach(rows) { row in
                    GridRow {
                        Text(row.id)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        StatusPill(row.status, tone: row.tone)
                        Text(row.algorithm)
                        Text(row.reward)
                            .font(.system(.caption, design: .monospaced))
                        Text(row.fitness)
                            .font(.system(.caption, design: .monospaced))
                        Text(row.generation)
                            .font(.system(.caption, design: .monospaced))
                        Text(row.updated)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)
        } label: {
            HStack {
                Label("Campaign Runs", systemImage: "list.bullet.rectangle")
                Spacer()
                Button {
                    model.loadLearningCampaignArtifacts()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var headerRow: some View {
        GridRow {
            Text("Run ID")
            Text("Status")
            Text("Algorithm")
            Text("Reward")
            Text("Fitness")
            Text("Generation")
            Text("Updated")
        }
        .foregroundStyle(.secondary)
        .font(.caption.weight(.semibold))
    }

    private var rows: [LearningExperimentRow] {
        guard let state = model.learningCampaignState else {
            return [
                LearningExperimentRow(
                    id: "current",
                    status: model.isLearningCampaignRunning ? "running" : "idle",
                    tone: model.isLearningCampaignRunning ? .success : .neutral,
                    algorithm: "GA",
                    reward: latestReward,
                    fitness: "--",
                    generation: "--",
                    updated: model.learningCampaignLatestEvent ?? "--"
                )
            ]
        }

        let latest = state.latestGenerations.prefix(5).map { row in
            LearningExperimentRow(
                id: row.id,
                status: row.accepted ? "accepted" : (row.incumbentImproved ? "improved" : "searching"),
                tone: row.accepted ? .success : (row.incumbentImproved ? .info : .neutral),
                algorithm: "GA",
                reward: latestReward,
                fitness: format(row.bestFitness),
                generation: "\(row.generationIndex + 1)",
                updated: row.createdAt.formatted(date: .omitted, time: .shortened)
            )
        }
        if !latest.isEmpty {
            return Array(latest)
        }
        return [
            LearningExperimentRow(
                id: state.artifactDirectory.lastPathComponent,
                status: state.statusLabel,
                tone: state.isActive ? .info : .neutral,
                algorithm: "GA",
                reward: latestReward,
                fitness: format(state.bestDelta),
                generation: "--",
                updated: state.latestEvent?.event ?? "--"
            )
        ]
    }

    private var latestReward: String {
        guard let value = model.rewardAverageSamples.last?.value ?? model.loopScoreSamples.last?.value else {
            return "--"
        }
        return String(format: "%.2f", value)
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.2f", value)
    }
}

struct LearningExperimentRow: Identifiable {
    let id: String
    let status: String
    let tone: StatusPill.Tone
    let algorithm: String
    let reward: String
    let fitness: String
    let generation: String
    let updated: String
}
