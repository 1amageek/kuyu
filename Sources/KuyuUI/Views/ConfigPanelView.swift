import SwiftUI
import KuyuCore
import KuyuProfiles

public struct ConfigPanelView: View {
    @Bindable var model: SimulationViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)
                .foregroundStyle(.primary)

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
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        .font(.body)
                        .foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Task", selection: $model.taskMode) {
                        ForEach(SimulationTaskMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    switch model.taskMode {
                    case .lift:
                        Text("KUY-LIFT-1: Z-axis lift hold (quad, no attitude scoring).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .singleLift:
                        Text("KUY-SLIFT-1: Single-prop takeoff from ground to 0.5m hover.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .attitude:
                        Text("KUY-ATT-1 (M1): Attitude stabilization, swappability, HF stress.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("Model") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Descriptor path", text: $model.modelDescriptorPath)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            model.emitUIAction(level: .info, message: "Descriptor path updated", action: "setDescriptorPath", metadata: [
                                "path": model.modelDescriptorPath
                            ])
                        }
                    HStack(spacing: 8) {
                        Button("Use Bundled") {
                            if let path = KuyuUIModelPaths.bundledDescriptorPath() {
                                model.setModelDescriptorPath(path, source: "bundled")
                            } else {
                                model.emitUIAction(level: .warning, message: "Bundled model not found", action: "setDescriptorPath", metadata: [
                                    "source": "bundled",
                                    "reason": "notFound"
                                ])
                            }
                        }
                        Button("Use Local") {
                            if let path = KuyuUIModelPaths.localDescriptorPath() {
                                model.setModelDescriptorPath(path, source: "local")
                            } else if let source = KuyuUIModelPaths.sourceRootDescriptorPath() {
                                model.setModelDescriptorPath(source, source: "source")
                            } else {
                                model.emitUIAction(level: .warning, message: "Local model not found", action: "setDescriptorPath", metadata: [
                                    "source": "local",
                                    "reason": "notFound"
                                ])
                            }
                        }
                    }
                    .font(.callout)
                    Toggle("Render asset", isOn: $model.useRenderAssets)
                    Text("RobotDescriptor (e.g. Models/Robot/robot.robot.json)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }

            GroupBox("Descriptor Summary") {
                VStack(alignment: .leading, spacing: 6) {
                    if let descriptor = model.currentDescriptor() {
                        SummaryLine(label: "robotID", value: descriptor.robot.robotID)
                        SummaryLine(label: "name", value: descriptor.robot.name)
                        SummaryLine(label: "category", value: descriptor.robot.category)
                        SummaryLine(label: "engine", value: descriptor.physics.engine.id)
                        SummaryLine(label: "motorNerve stages", value: "\(descriptor.motorNerve.stages.count)")
                    } else if let error = model.currentDescriptorError() {
                        Text("Descriptor error: \(error)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Descriptor not loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            model.emitUIAction(level: .info, message: "Environment logging config toggled", action: "toggleEnvLogging", metadata: [
                                "enabled": "\(enabled)"
                            ])
                        }

                    TextField("Label", text: $model.logLabel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.logLabel) { _, _ in
                            model.refreshLogger()
                        }
                        .onSubmit {
                            model.emitUIAction(level: .info, message: "Log label updated", action: "setLogLabel", metadata: [
                                "label": model.logLabel
                            ])
                        }

                    Picker("Level", selection: $model.logLevel) {
                        ForEach(LogLevelOption.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: model.logLevel) { _, level in
                        model.refreshLogger()
                        model.emitUIAction(level: .info, message: "Log level updated", action: "setLogLevel", metadata: [
                            "level": level.rawValue
                        ])
                    }

                    TextField("Log directory", text: $model.logDirectory)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            model.emitUIAction(level: .info, message: "Log directory updated", action: "setLogDirectory", metadata: [
                                "path": model.logDirectory
                            ])
                        }
                }
                .padding(.top, 6)
            }
        }
        .font(.body)
        .foregroundStyle(.primary)
        .controlSize(.small)
    }
}

private struct SummaryLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    ConfigPanelView(model: KuyuUIPreviewFactory.model())
        .frame(width: 280)
}
