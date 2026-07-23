import KuyuScenarios
import SwiftUI

struct ExperimentDesignView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    LabeledContent("Starter", value: model.learningStarterProjectStatus)
                    TextField("Experiment Name", text: $model.learningCampaignExperimentName)
                    TextField("Description", text: $model.learningCampaignExperimentDescription, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Tags", text: $model.learningCampaignTagsText)
                    Picker("Template", selection: $model.taskMode) {
                        ForEach(SimulationTaskMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Picker("Compute Target", selection: $model.determinismSelection) {
                        ForEach(DeterminismSelection.allCases) { tier in
                            Text(tier.rawValue).tag(tier)
                        }
                    }
                    TextField("Source Checkpoint", text: $model.learningCampaignSourceCheckpointPath)
                    TextField("Artifact Root", text: $model.learningCampaignArtifactDirectory)
                        .disabled(model.isLearningCampaignRunning)
                    Toggle("Compact Artifact Retention", isOn: $model.learningCampaignCompactRetention)
                    Button {
                        model.prepareStarterLearningProject()
                    } label: {
                        Label("Reset to Starter Project", systemImage: "arrow.counterclockwise")
                    }
                }
                .textFieldStyle(.roundedBorder)
            } label: {
                Label("Experiment Design", systemImage: "doc.badge.gearshape")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    StatRow(label: "Environment", value: model.taskMode.rawValue)
                    StatRow(label: "Seed Count", value: "\(model.learningCampaignSeedCount)")
                    StatRow(label: "Checkpoint Policy", value: "strict accepted checkpoint")
                    StatRow(label: "Launch Preset", value: model.learningCampaignPreset.rawValue)
                    StatRow(label: "Strategy", value: model.learningStrategySelection.rawValue)
                }
            } label: {
                Label("Summary", systemImage: "list.bullet.rectangle")
            }
        }
    }
}
