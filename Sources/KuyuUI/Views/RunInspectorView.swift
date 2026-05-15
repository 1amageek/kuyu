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
                runState
                actions
                artifacts
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
                    openWindow(id: BoundedWindowID.analysis.rawValue)
                }
                Button("Open Report") {
                    openWindow(id: BoundedWindowID.report.rawValue)
                }
                Button("Rerun") {
                    simulationModel.startLearningCampaign()
                }
                Button("Continue From Checkpoint") {
                    simulationModel.continueLearningCampaignFromLastCheckpoint()
                }
                .disabled(!simulationModel.canContinueLearningCampaign)
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

    private var runState: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Status", value: simulationModel.learningCampaignState?.statusLabel ?? "--", compact: true)
                StatRow(label: "Validation", value: simulationModel.learningCampaignState?.validationLabel ?? "--", compact: true)
                StatRow(label: "Accepted", value: acceptedText, compact: true)
                if let state = simulationModel.learningCampaignState, state.hasTrainingStageIdentity {
                    StatRow(label: "Stage", value: state.trainingStageLabel, compact: true)
                    StatRow(label: "Stage Kind", value: state.trainingStageKindLabel, compact: true)
                }
                StatRow(label: "Latest Phase", value: simulationModel.learningCampaignCurrentPhase, compact: true)
                if let reason = primaryFailureReason {
                    StatRow(label: "Primary Issue", value: reason, compact: true)
                }
            }
        } label: {
            Label("Run State", systemImage: "gauge.with.dots.needle.bottom.50percent")
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

    private var acceptedText: String {
        guard let state = simulationModel.learningCampaignState else { return "--" }
        return "\(state.acceptedCount)/\(state.seedCount)"
    }

    private var primaryFailureReason: String? {
        if let stateReason = simulationModel.learningCampaignState?.primaryFailureReason {
            return stateReason
        }
        if let gateReason = simulationModel.lastPostRegressionGate?.primaryRejectReason {
            return gateReason
        }
        return simulationModel.learningCampaignError
    }
}
