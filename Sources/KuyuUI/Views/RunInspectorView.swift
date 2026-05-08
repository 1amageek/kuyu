import SwiftUI

struct RunInspectorView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: AppViewModel

    private var simulationModel: SimulationViewModel {
        model.simulationViewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                metadata
                actions
                artifacts
                notes
            }
            .padding(KuyuSpacing.md)
        }
    }

    private var metadata: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Run ID", value: simulationModel.selectedRun?.id.uuidString.prefix(8).description ?? "--", compact: true)
                StatRow(label: "Progress", value: simulationModel.learningCampaignCurrentPhase, compact: true)
                StatRow(label: "Reward", value: reward, compact: true)
                StatRow(label: "Fitness", value: fitness, compact: true)
                StatRow(label: "Config Snapshot", value: simulationModel.learningCampaignState?.suiteSummary ?? "--", compact: true)
            }
        } label: {
            Label("Run Inspector", systemImage: "sidebar.trailing")
        }
    }

    private var actions: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                Button("Open Simulation") {
                    openWindow(id: BoundedWindowID.simulation.rawValue)
                }
                Button("Open Analysis") {
                    model.selectedWorkspace = .analysis
                }
                Button("Open Report") {
                    model.selectedWorkspace = .report
                }
                Button("Rerun") {
                    simulationModel.startLearningCampaign()
                }
                Button(role: .destructive) {
                    simulationModel.clearRuns()
                } label: {
                    Text("Delete")
                }
            }
        } label: {
            Label("Actions", systemImage: "play.circle")
        }
    }

    private var artifacts: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Root", value: artifactRoot, compact: true)
                StatRow(label: "Final Checkpoint", value: finalCheckpoint, compact: true)
                StatRow(label: "Validation", value: simulationModel.learningCampaignState?.validationLabel ?? "--", compact: true)
            }
        } label: {
            Label("Artifacts", systemImage: "shippingbox")
        }
    }

    private var notes: some View {
        GroupBox {
            Text(simulationModel.learningCampaignLatestEvent ?? "No notes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } label: {
            Label("Notes", systemImage: "note.text")
        }
    }

    private var reward: String {
        guard let value = simulationModel.rewardAverageSamples.last?.value ?? simulationModel.loopScoreSamples.last?.value else { return "--" }
        return String(format: "%.2f", value)
    }

    private var fitness: String {
        guard let value = simulationModel.learningCampaignState?.generations.compactMap(\.bestFitness).max() else { return "--" }
        return String(format: "%.2f", value)
    }

    private var artifactRoot: String {
        guard let path = simulationModel.learningCampaignState?.artifactDirectory.path else { return "--" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var finalCheckpoint: String {
        guard let path = simulationModel.learningCampaignState?.finalCheckpoint else { return "--" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
