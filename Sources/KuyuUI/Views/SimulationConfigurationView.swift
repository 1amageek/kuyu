import SwiftUI
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public struct SimulationConfigurationView: View {
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
                    } else if model.controllerSelection == .teacherBaseline {
                        Text("Teacher Baseline may use scenario reference state for dataset/reference runs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if model.controllerSelection == .sensorBaseline {
                        Text("Sensor Baseline uses sensor-derived state only and does not receive hidden scenario attitude.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }

            GroupBox("Controller Gains") {
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    NumberFieldView(
                        label: "kp", value: $model.kp, range: 0 ... 100, step: 0.5,
                        help: "Proportional attitude gain (rad error → rate)."
                    )
                    NumberFieldView(
                        label: "kd", value: $model.kd, range: 0 ... 50, step: 0.1,
                        help: "Derivative (rate damping) gain."
                    )
                    NumberFieldView(
                        label: "yaw", value: $model.yawDamping, range: 0 ... 50, step: 0.1,
                        help: "Yaw-axis damping gain."
                    )
                    NumberFieldView(
                        label: "hover", value: $model.hoverThrustScale, range: 0.1 ... 3.0, step: 0.05,
                        help: "Hover thrust scale (1.0 = exact weight compensation)."
                    )
                }
                .padding(.top, 6)
            }
            .disabled(!model.controllerSelection.isBaselineController)

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
                    TextField(
                        "Robot manifest path",
                        text: Binding(
                            get: { model.robotManifestPath },
                            set: { model.setRobotManifestPath($0, source: "textField", emitLog: false) }
                        )
                    )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            model.setRobotManifestPath(model.robotManifestPath, source: "textField")
                        }
                    HStack(spacing: 8) {
                        Button("Use Bundled") {
                            if let path = KuyuUIModelPaths.bundledRobotManifestPath() {
                                model.setRobotManifestPath(path, source: "bundled")
                            } else {
                                model.emitUIAction(level: .warning, message: "Bundled model not found", action: "setRobotManifestPath", metadata: [
                                    "source": "bundled",
                                    "reason": "notFound"
                                ])
                            }
                        }
                        Button("Use Local") {
                            if let path = KuyuUIModelPaths.localRobotManifestPath() {
                                model.setRobotManifestPath(path, source: "local")
                            } else if let source = KuyuUIModelPaths.sourceRootRobotManifestPath() {
                                model.setRobotManifestPath(source, source: "source")
                            } else {
                                model.emitUIAction(level: .warning, message: "Local model not found", action: "setRobotManifestPath", metadata: [
                                    "source": "local",
                                    "reason": "notFound"
                                ])
                            }
                        }
                        Button("Use RoArm M1") {
                            model.setRobotManifestPath(
                                KuyuUIModelPaths.defaultRoArmM1RobotManifestPath(),
                                source: "roarm-m1"
                            )
                        }
                    }
                    .font(.callout)
                    Toggle("Render asset", isOn: $model.useRenderAssets)
                    Text("Robot manifest (e.g. Models/Robot/robot.kuyurobot.json)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }

            GroupBox("Descending Intent") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Comma-separated values (e.g. 0.5,0.0,-0.1)", text: $model.descendingVectorText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            model.emitUIAction(level: .info, message: "Descending channels updated", action: "setDescendingChannels", metadata: [
                                "raw": model.descendingVectorText
                            ])
                        }

                    TextField("Program (e.g. 0:0.4,0,0,0;1.0:0.6,0,0,0)", text: $model.descendingProgramText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            model.emitUIAction(level: .info, message: "Descending program updated", action: "setDescendingProgram", metadata: [
                                "raw": model.descendingProgramText
                            ])
                        }

                    let descendingChannels = model.embodimentDescendingChannelIDs()
                    if descendingChannels.isEmpty {
                        Text("Current embodiment does not define control.descendingChannels. Input is ignored.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Channel order: \(descendingChannels.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Set either vector or program (not both). Leave both empty for zero intent.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }

            GroupBox("Robot Summary") {
                VStack(alignment: .leading, spacing: 6) {
                    if let manifest = model.currentRobotManifest(), let embodiment = model.currentEmbodiment() {
                        SummaryLine(label: "robotID", value: manifest.robotID)
                        SummaryLine(label: "name", value: manifest.name)
                        SummaryLine(label: "category", value: manifest.category)
                        SummaryLine(label: "contract", value: embodiment.contractID)
                        SummaryLine(label: "motorNerve stages", value: "\(embodiment.motorNerve.stages.count)")
                        SummaryLine(label: "descending signals", value: "\((embodiment.signals.descending ?? []).count)")
                        SummaryLine(label: "descending channels", value: "\((embodiment.control.descendingChannels ?? []).count)")
                    } else if let error = model.currentRobotLoadError() {
                        Text("Robot contract error: \(error)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Robot manifest not loaded")
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
    SimulationConfigurationView(model: KuyuUIPreviewFactory.model())
        .frame(width: 280)
}
