import SwiftUI

public struct TrainingConfigPanelView: View {
    @Bindable var model: SimulationViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training")
                .font(KuyuUITheme.titleFont(size: 16))
                .foregroundStyle(KuyuUITheme.textPrimary)

            GroupBox("Model") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.selectedModel?.name ?? "Unselected")
                        .font(KuyuUITheme.bodyFont(size: 12))
                        .foregroundStyle(KuyuUITheme.textPrimary)
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
                    .font(KuyuUITheme.bodyFont(size: 11))
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
                    .font(KuyuUITheme.bodyFont(size: 11))
                    .disabled(model.selectedRun == nil)
                    Text("Exports per-scenario datasets (meta.json + records.jsonl).")
                        .font(KuyuUITheme.bodyFont(size: 10))
                        .foregroundStyle(KuyuUITheme.textSecondary)
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
                                .font(KuyuUITheme.bodyFont(size: 11))
                                .foregroundStyle(KuyuUITheme.textSecondary)
                        }
                        Stepper(value: $model.trainingEpochs, in: 1...50) {
                            Text("Epochs: \(model.trainingEpochs)")
                                .font(KuyuUITheme.bodyFont(size: 11))
                                .foregroundStyle(KuyuUITheme.textSecondary)
                        }
                    }
                    NumberFieldView(label: "lr", value: $model.trainingLearningRate)
                    Toggle("Use aux loss", isOn: $model.trainingUseAux)
                    Toggle("Quality gating", isOn: $model.trainingUseQualityGating)

                    HStack(spacing: 8) {
                        Button(model.isTraining ? "Training…" : "Train Core") {
                            model.trainCoreModel()
                        }
                        .disabled(model.isTraining || model.isRunning || model.isLoopRunning)

                        if let loss = model.lastTrainingLoss {
                            Text("loss \(String(format: "%.6f", loss))")
                                .font(KuyuUITheme.monoFont(size: 10))
                                .foregroundStyle(KuyuUITheme.textSecondary)
                        }
                    }
                    .font(KuyuUITheme.bodyFont(size: 11))
                }
                .padding(.top, 6)
            }

            GroupBox("Training Loop") {
                VStack(alignment: .leading, spacing: 8) {
                    Stepper(value: $model.loopMaxIterations, in: 1...200) {
                        Text("Iterations: \(model.loopMaxIterations)")
                            .font(KuyuUITheme.bodyFont(size: 11))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    }
                    Stepper(value: $model.loopEvaluationInterval, in: 1...20) {
                        Text("Eval interval: \(model.loopEvaluationInterval)")
                            .font(KuyuUITheme.bodyFont(size: 11))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    }
                    Stepper(value: $model.loopPatience, in: 0...20) {
                        Text("Patience: \(model.loopPatience)")
                            .font(KuyuUITheme.bodyFont(size: 11))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    }
                    Stepper(value: $model.loopMaxFailures, in: 1...10) {
                        Text("Max failures: \(model.loopMaxFailures)")
                            .font(KuyuUITheme.bodyFont(size: 11))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    }
                    NumberFieldView(label: "minΔ", value: $model.loopMinDelta)
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
                    .font(KuyuUITheme.bodyFont(size: 11))

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
                        .font(KuyuUITheme.monoFont(size: 10))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                        Text(model.loopStatusMessage)
                            .font(KuyuUITheme.bodyFont(size: 10))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    }
                }
                .padding(.top, 6)
            }
        }
        .font(KuyuUITheme.bodyFont(size: 12))
        .foregroundStyle(KuyuUITheme.textPrimary)
    }
}

#Preview {
    TrainingConfigPanelView(model: KuyuUIPreviewFactory.model())
        .frame(width: 280)
        .background(KuyuUITheme.background)
}
