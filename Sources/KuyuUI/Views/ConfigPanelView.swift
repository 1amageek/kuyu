import SwiftUI

struct ConfigPanelView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(KuyuUITheme.titleFont(size: 16))
                .foregroundStyle(KuyuUITheme.textPrimary)

            GroupBox("Controller Gains") {
                VStack(alignment: .leading, spacing: 8) {
                    NumberFieldView(label: "kp", value: $model.kp)
                    NumberFieldView(label: "kd", value: $model.kd)
                    NumberFieldView(label: "yaw", value: $model.yawDamping)
                    NumberFieldView(label: "hover", value: $model.hoverThrustScale)
                }
                .padding(.top, 6)
            }

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

            GroupBox("Learning") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Mode", selection: $model.learningMode) {
                        ForEach(LearningMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Learning applies actuator-side deltas inside DAL. Off disables updates.")
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
