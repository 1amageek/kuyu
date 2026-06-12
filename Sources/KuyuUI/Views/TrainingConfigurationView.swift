import SwiftUI

public struct TrainingConfigurationView: View {
    @Bindable var model: SimulationViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training")
                .font(.headline)
                .foregroundStyle(.primary)

            GroupBox("Model") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.selectedModel?.name ?? "Unselected")
                        .font(.body)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Button("New Model") {
                            model.createModel()
                        }
                        .disabled(model.isRunning || model.isTraining || model.isLoopRunning)
                        Button("Clear Training") {
                            model.clearTrainingState()
                        }
                        .disabled(model.isRunning || model.isTraining || model.isLoopRunning)
                    }
                    .font(.callout)
                }
                .padding(.top, 6)
            }

            GroupBox("Training Dataset") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Dataset output directory", text: $model.trainingDatasetDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("Export Training Dataset") {
                        model.exportTrainingDataset()
                    }
                    .font(.callout)
                    .disabled(model.selectedRun == nil)
                    Text("Exports per-scenario datasets (meta.json + records.jsonl).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }

            GroupBox("Training (MLX)") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Training dataset directory", text: $model.trainingInputDirectory)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 10) {
                        Stepper(value: $model.trainingSequenceLength, in: 4...64) {
                            Text("Sequence: \(model.trainingSequenceLength)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Stepper(value: $model.trainingEpochs, in: 1...50) {
                            Text("Epochs: \(model.trainingEpochs)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NumberFieldView(
                        label: "lr", value: $model.trainingLearningRate,
                        range: 0.00001 ... 1.0, step: 0.0005, fractionLength: 5,
                        help: "Learning rate."
                    )
                    Toggle("Use aux loss", isOn: $model.trainingUseAux)
                    Toggle("Quality gating", isOn: $model.trainingUseQualityGating)

                    HStack(spacing: 8) {
                        Button(model.isTraining ? "Training…" : "Train Core") {
                            model.trainCoreModel()
                        }
                        .disabled(model.isTraining || model.isRunning || model.isLoopRunning)

                        if let loss = model.lastTrainingLoss {
                            Text("loss \(String(format: "%.6f", loss))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
                .padding(.top, 6)
            }

            GroupBox("Training Loop") {
                VStack(alignment: .leading, spacing: 8) {
                    Stepper(value: $model.loopMaxIterations, in: 1...200) {
                        Text("Iterations: \(model.loopMaxIterations)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $model.loopEvaluationInterval, in: 1...20) {
                        Text("Eval interval: \(model.loopEvaluationInterval)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $model.loopPatience, in: 0...20) {
                        Text("Patience: \(model.loopPatience)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $model.loopMaxFailures, in: 1...10) {
                        Text("Max failures: \(model.loopMaxFailures)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    NumberFieldView(
                        label: "minΔ", value: $model.loopMinDelta,
                        range: 0.0 ... 1.0, step: 0.001, fractionLength: 4,
                        help: "Minimum score improvement to count as progress."
                    )
                    Toggle("Stop on pass", isOn: $model.loopStopOnPass)
                    Toggle("Auto backoff", isOn: $model.loopAllowAutoBackoff)

                    HStack(spacing: 8) {
                        Button("Start Loop") { model.startTrainingLoop() }
                            .disabled(model.isLoopRunning || model.isRunning)
                        Button(model.isLoopPaused ? "Resume" : "Pause") {
                            model.isLoopPaused ? model.resumeTrainingLoop() : model.pauseTrainingLoop()
                        }
                        .disabled(!model.isLoopRunning)
                        Button("Stop") { model.stopTrainingLoop() }
                            .disabled(!model.isLoopRunning)
                    }
                    .font(.callout)

                    if model.isLoopRunning || model.loopIteration > 0 {
                        HStack(spacing: 12) {
                            Text("Iter \(model.loopIteration)")
                            if let best = model.loopBestScore {
                                Text("Best \(String(format: "%.3f", best))")
                            }
                            if let last = model.loopLastScore {
                                Text("Last \(String(format: "%.3f", last))")
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        Text(model.loopStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }

            GroupBox("Learning Campaign") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Source checkpoint", text: $model.learningCampaignSourceCheckpointPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Best") {
                            model.useCurrentBestLearningCheckpoint()
                        }
                    }
                    TextField("Campaign artifact directory", text: $model.learningCampaignArtifactDirectory)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button("New Root") {
                            model.prepareNewLearningCampaignArtifactRoot()
                        }
                        TextField("Suites", text: $model.learningCampaignSuites)
                            .textFieldStyle(.roundedBorder)
                    }
                    Stepper(value: $model.learningCampaignSeedCount, in: 1...20) {
                        Text("Seeds: \(model.learningCampaignSeedCount)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $model.learningCampaignGenerations, in: 1...10_000) {
                        Text("Safety budget: \(model.learningCampaignGenerations) generations")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $model.learningCampaignPopulation, in: 1...512) {
                        Text("Population: \(model.learningCampaignPopulation)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $model.learningCampaignWorkers, in: 1...16) {
                        Text("Workers: \(model.learningCampaignWorkers)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Adaptive mutation", isOn: $model.learningCampaignAdaptiveMutation)
                    Toggle("Compact artifacts", isOn: $model.learningCampaignCompactRetention)
                    ProgressView(value: model.learningCampaignProgressFraction, total: 1)
                    HStack(spacing: 8) {
                        Text("Phase: \(model.learningCampaignCurrentPhase)")
                        if let event = model.learningCampaignLatestEvent {
                            Text(event)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Use Current") {
                            model.useCurrentLearningCampaignArtifactRoot()
                        }
                        Button("Load") {
                            model.loadLearningCampaignArtifacts()
                        }
                        Button(model.learningCampaignMonitorEnabled ? "Stop Watch" : "Watch") {
                            if model.learningCampaignMonitorEnabled {
                                model.stopLearningCampaignMonitoring()
                            } else {
                                model.startLearningCampaignMonitoring()
                            }
                        }
                    }
                    .font(.callout)
                    if let state = model.learningCampaignState {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(state.statusLabel) | \(state.task) | \(state.acceptedCount)/\(state.seedCount) accepted")
                            if let delta = state.bestDelta {
                                Text("Best Delta \(String(format: "%.3f", delta))")
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    } else if let error = model.learningCampaignError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.top, 6)
            }
        }
        .font(.body)
        .foregroundStyle(.primary)
    }
}

#Preview {
    TrainingConfigurationView(model: KuyuUIPreviewFactory.model())
        .frame(width: 280)
}
