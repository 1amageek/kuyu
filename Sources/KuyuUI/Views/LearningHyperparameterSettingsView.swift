import SwiftUI

struct LearningHyperparameterSettingsView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(spacing: KuyuSpacing.md) {
            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    IntegerStepperView(label: "Seed Count", value: $model.learningCampaignSeedCount, range: 1...64)
                    IntegerStepperView(label: "Population", value: $model.learningCampaignPopulation, range: 1...512)
                    IntegerStepperView(label: "Safety Generation Budget", value: $model.learningCampaignGenerations, range: 1...10_000)
                    IntegerStepperView(label: "Elite Count", value: $model.learningCampaignEliteCount, range: 1...64)
                    IntegerStepperView(label: "Workers", value: $model.learningCampaignWorkers, range: 1...64)
                    IntegerStepperView(
                        label: "Candidate Concurrency",
                        value: $model.learningCampaignCandidateEvaluationConcurrency,
                        range: 1...64
                    )
                    DoubleSliderView(
                        label: "Mutation Rate",
                        value: $model.learningCampaignMutationRate,
                        range: 0...1,
                        display: String(format: "%.3f", model.learningCampaignMutationRate)
                    )
                    DoubleSliderView(
                        label: "Mutation Noise",
                        value: $model.learningCampaignMutationNoiseScale,
                        range: 0...0.25,
                        display: String(format: "%.4f", model.learningCampaignMutationNoiseScale)
                    )
                    DoubleSliderView(
                        label: "Minimum Improvement",
                        value: $model.learningCampaignMinimumIncumbentImprovement,
                        range: 0...1,
                        display: String(format: "%.3f", model.learningCampaignMinimumIncumbentImprovement)
                    )
                }
            } label: {
                Label("Hyperparameters", systemImage: "slider.horizontal.3")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    TextField("Suites", text: $model.learningCampaignSuites)
                    TextField("Source Checkpoint", text: $model.learningCampaignSourceCheckpointPath)
                    TextField("Artifact Root", text: $model.learningCampaignArtifactDirectory)
                        .disabled(model.isLearningCampaignRunning)
                    Toggle("Adaptive Mutation", isOn: $model.learningCampaignAdaptiveMutation)
                    Toggle("Compact Retention", isOn: $model.learningCampaignCompactRetention)
                    Toggle("Monitor Artifacts", isOn: $model.learningCampaignMonitorEnabled)
                        .onChange(of: model.learningCampaignMonitorEnabled) { _, isEnabled in
                            if isEnabled {
                                model.startLearningCampaignMonitoring()
                            } else {
                                model.stopLearningCampaignMonitoring()
                            }
                        }
                }
                .textFieldStyle(.roundedBorder)
            } label: {
                Label("Learning Settings", systemImage: "gearshape")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    StatRow(label: "Status", value: model.learningCampaignState?.statusLabel ?? "--", compact: true)
                    StatRow(label: "Validation", value: model.learningCampaignState?.validationLabel ?? "--", compact: true)
                    StatRow(label: "Accepted", value: acceptedValue, compact: true)
                    StatRow(label: "Final Checkpoint", value: finalCheckpoint, compact: true)
                    if let error = model.learningCampaignError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(4)
                    }
                }
            } label: {
                Label("Decision", systemImage: "checkmark.seal")
            }
        }
    }

    private var acceptedValue: String {
        guard let state = model.learningCampaignState else { return "--" }
        return "\(state.acceptedCount) / \(state.seedCount)"
    }

    private var finalCheckpoint: String {
        guard let value = model.learningCampaignState?.finalCheckpoint else { return "--" }
        return URL(fileURLWithPath: value).lastPathComponent
    }
}
