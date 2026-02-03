import SwiftUI
import KuyuCore

struct ConfigPanelView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(KuyuUITheme.titleFont(size: 16))
                .foregroundStyle(KuyuUITheme.textPrimary)

            GroupBox("Controller") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Type", selection: $model.controllerSelection) {
                        ForEach(ControllerSelection.allCases) { controller in
                            Text(controller.rawValue).tag(controller)
                        }
                    }
                    .pickerStyle(.menu)
                    if model.controllerSelection == .manasMLX {
                        Text("ManasMLX uses learned Core/Reflex. Gains are ignored.")
                            .font(KuyuUITheme.bodyFont(size: 10))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    }
                }
                .padding(.top, 6)
            }

            GroupBox("Controller Gains") {
                VStack(alignment: .leading, spacing: 8) {
                    NumberFieldView(label: "kp", value: $model.kp)
                    NumberFieldView(label: "kd", value: $model.kd)
                    NumberFieldView(label: "yaw", value: $model.yawDamping)
                    NumberFieldView(label: "hover", value: $model.hoverThrustScale)
                }
                .padding(.top, 6)
            }
            .disabled(model.controllerSelection != .baseline)

            GroupBox("Schedule") {
                Stepper(value: $model.cutPeriodSteps, in: 1...10) {
                    Text("CUT period steps: \(model.cutPeriodSteps)")
                        .font(KuyuUITheme.bodyFont(size: 12))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                }
                .padding(.top, 4)
            }

            GroupBox("Determinism") {
                Picker("Tier", selection: $model.determinismSelection) {
                    ForEach(DeterminismSelection.allCases) { tier in
                        Text(tier.rawValue).tag(tier)
                    }
                }
                .pickerStyle(.menu)
            }

            GroupBox("Training Suite") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("KUY-ATT-1 (M1)")
                        .font(KuyuUITheme.bodyFont(size: 12))
                        .foregroundStyle(KuyuUITheme.textPrimary)
                    Text("Attitude stabilization, swappability events, HF stress.")
                        .font(KuyuUITheme.bodyFont(size: 10))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                }
                .padding(.top, 4)
            }

            GroupBox("Model") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Descriptor path", text: $model.modelDescriptorPath)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button("Use Bundled") {
                            if let path = KuyuUIModelPaths.bundledDescriptorPath() {
                                model.setModelDescriptorPath(path, source: "bundled")
                            } else {
                                model.emitTerminal(level: .warning, message: "Bundled model not found")
                            }
                        }
                        Button("Use Local") {
                            if let path = KuyuUIModelPaths.localDescriptorPath() {
                                model.setModelDescriptorPath(path, source: "local")
                            } else if let source = KuyuUIModelPaths.sourceRootDescriptorPath() {
                                model.setModelDescriptorPath(source, source: "source")
                            } else {
                                model.emitTerminal(level: .warning, message: "Local model not found")
                            }
                        }
                    }
                    .font(KuyuUITheme.bodyFont(size: 11))
                    Text("URDF/SDF descriptor (e.g. Models/QuadRef/quadref.model.json)")
                        .font(KuyuUITheme.bodyFont(size: 10))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                }
                .padding(.top, 6)
            }

            GroupBox("UI Profile") {
                Picker("Robot profile", selection: $model.robotProfileSelection) {
                    ForEach(RobotProfileSelection.allCases) { profile in
                        Text(profile.rawValue).tag(profile)
                    }
                }
                .pickerStyle(.menu)
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
                        .disabled(model.isTraining)

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

            GroupBox("Logging") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use environment config", isOn: $model.useEnvironmentConfig)
                        .onChange(of: model.useEnvironmentConfig) { _, enabled in
                            if enabled {
                                model.applyEnvironmentConfig()
                            } else {
                                model.refreshLogger()
                            }
                        }

                    TextField("Label", text: $model.logLabel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.logLabel) { _, _ in
                            model.refreshLogger()
                        }

                    Picker("Level", selection: $model.logLevel) {
                        ForEach(LogLevelOption.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: model.logLevel) { _, _ in
                        model.refreshLogger()
                    }

                    TextField("Log directory", text: $model.logDirectory)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.top, 6)
            }
        }
        .font(KuyuUITheme.bodyFont(size: 12))
        .foregroundStyle(KuyuUITheme.textPrimary)
        .padding(12)
        .background(KuyuUITheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(KuyuUITheme.panelHighlight, lineWidth: 1)
        )
    }
}

#Preview {
    ConfigPanelView(model: KuyuUIPreviewFactory.model())
        .frame(width: 280)
        .background(KuyuUITheme.background)
}
