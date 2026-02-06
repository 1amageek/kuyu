import SwiftUI
import KuyuCore
import KuyuProfiles

public struct TrainingDashboardView: View {
    @Bindable var model: SimulationViewModel
    let roll: Double
    let pitch: Double
    let yaw: Double
    let position: Axis3
    let renderInfo: RenderAssetInfo?

    public init(
        model: SimulationViewModel,
        roll: Double,
        pitch: Double,
        yaw: Double,
        position: Axis3,
        renderInfo: RenderAssetInfo?
    ) {
        self.model = model
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
        self.position = position
        self.renderInfo = renderInfo
    }

    public var body: some View {
        VSplitView {
            HSplitView {
                WorldRealityView(
                    roll: roll,
                    pitch: pitch,
                    yaw: yaw,
                    position: position,
                    label: renderInfo?.name ?? "Robot proxy",
                    renderInfo: renderInfo
                )
                TrainingStatusPanel(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HSplitView {
                TrainingChartsGrid(model: model)
                    .frame(minWidth: 520)
                LogConsoleView(entries: model.logStore.entries, onClear: model.logStore.clear)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KuyuUITheme.background)
    }
}

private struct TrainingStatusPanel: View {
    @Bindable var model: SimulationViewModel
    @State private var inspectorTab: InspectorTab = .kuyu

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusHeader
                ProgressView(value: progressValue, total: progressTotal)
                statusGrid
                controlBoundaryPanel
                manasSignalFlowPanel
                hoverTestPanel
                inspectorPicker
                if inspectorTab == .kuyu {
                    SensorSignalsPanel(model: model)
                    ActuatorSignalsPanel(model: model)
                    MotorNerveChainPanel(model: model)
                    ManualActuatorControlPanel(model: model)
                } else {
                    ManasSignalsPanel(model: model)
                }
                trainingSummary
                Spacer()
            }
        }
        .contentMargins(8)
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Training Status")
                .font(KuyuUITheme.titleFont(size: 16))
                .foregroundStyle(KuyuUITheme.textPrimary)
            Text(currentStatus)
                .font(KuyuUITheme.bodyFont(size: 12))
                .foregroundStyle(KuyuUITheme.textSecondary)
        }
    }

    private var statusGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrainingStatLine(label: "Model", value: model.selectedModel?.name ?? "None")
            TrainingStatLine(label: "Task", value: model.taskMode.rawValue)
            TrainingStatLine(label: "Loop", value: "\(model.loopIteration)/\(model.loopMaxIterations)")
            TrainingStatLine(label: "Best Score", value: formatted(model.loopBestScore))
            TrainingStatLine(label: "Last Score", value: formatted(model.loopLastScore))
            TrainingStatLine(label: "Last Loss", value: formatted(model.lastTrainingLoss))
        }
    }

    private var inspectorPicker: some View {
        Picker("Inspector", selection: $inspectorTab) {
            ForEach(InspectorTab.allCases, id: \.self) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: inspectorTab) { _, tab in
            model.emitUIAction(level: .info, message: "Inspector tab changed", action: "setInspectorTab", metadata: [
                "tab": tab.label
            ])
        }
    }

    private var controlBoundaryPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Control Boundary")
                .font(KuyuUITheme.titleFont(size: 12))
                .foregroundStyle(KuyuUITheme.textPrimary)
            HStack(spacing: 6) {
                Text("MotorNerve: Descriptor-defined mapping")
                    .font(KuyuUITheme.monoFont(size: 10))
                    .foregroundStyle(KuyuUITheme.textPrimary)
                Text("Manas: Learnable Core + Reflex")
                    .font(KuyuUITheme.monoFont(size: 10))
                    .foregroundStyle(KuyuUITheme.textSecondary)
            }
            Text("MotorNerve is a protocol mapping, not a safety filter. Reflex applies bounded corrections and MotorNerve remains deterministic for a given descriptor.")
                .font(KuyuUITheme.bodyFont(size: 10))
                .foregroundStyle(KuyuUITheme.textSecondary)
        }
        .padding(10)
        .background(KuyuUITheme.panelHighlight.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var trainingSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Loop")
                .font(KuyuUITheme.titleFont(size: 13))
                .foregroundStyle(KuyuUITheme.textPrimary)
            Text(model.loopStatusMessage.isEmpty ? "Idle" : model.loopStatusMessage)
                .font(KuyuUITheme.bodyFont(size: 12))
                .foregroundStyle(KuyuUITheme.textSecondary)
            if model.isTraining {
                Text("Supervised training running")
                    .font(KuyuUITheme.bodyFont(size: 11))
                    .foregroundStyle(KuyuUITheme.accent)
            }
        }
        .padding(10)
        .background(KuyuUITheme.panelHighlight.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var manasSignalFlowPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manas Signal Flow")
                .font(KuyuUITheme.titleFont(size: 12))
                .foregroundStyle(KuyuUITheme.textPrimary)
            Text("Runtime control path (signals flow left → right)")
                .font(KuyuUITheme.bodyFont(size: 10))
                .foregroundStyle(KuyuUITheme.textSecondary)
            ManasSignalFlowDiagram()
        }
        .padding(10)
        .background(KuyuUITheme.panelHighlight.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var hoverTestPanel: some View {
        let isLocked = model.isLoopRunning || model.isTraining
        return VStack(alignment: .leading, spacing: 6) {
            Text("RealityView Hover Test")
                .font(KuyuUITheme.titleFont(size: 12))
                .foregroundStyle(KuyuUITheme.textPrimary)
            Text("Adjust hover thrust scale to verify vertical motion.")
                .font(KuyuUITheme.bodyFont(size: 10))
                .foregroundStyle(KuyuUITheme.textSecondary)
            HStack(spacing: 6) {
                Button("0.9 ↓") {
                    model.setHoverThrustScale(0.9, source: "ui.hoverTestDown")
                }
                Button("1.0 •") {
                    model.setHoverThrustScale(1.0, source: "ui.hoverTestNeutral")
                }
                Button("1.1 ↑") {
                    model.setHoverThrustScale(1.1, source: "ui.hoverTestUp")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isLocked)
            .opacity(isLocked ? 0.5 : 1.0)
            if isLocked {
                Text("Disabled while training loop is running.")
                    .font(KuyuUITheme.bodyFont(size: 10))
                    .foregroundStyle(KuyuUITheme.warning)
            }
            Text("Current: \(String(format: "%.2f", model.hoverThrustScale))")
                .font(KuyuUITheme.monoFont(size: 10))
                .foregroundStyle(KuyuUITheme.textSecondary)
        }
        .padding(10)
        .background(KuyuUITheme.panelHighlight.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var currentStatus: String {
        if model.isTraining { return "Supervised training" }
        if model.isLoopRunning { return model.isLoopPaused ? "Loop paused" : "Loop running" }
        if model.isRunning { return "Simulation running" }
        return "Idle"
    }

    private var progressValue: Double {
        Double(min(model.loopIteration, max(model.loopMaxIterations, 1)))
    }

    private var progressTotal: Double {
        Double(max(model.loopMaxIterations, 1))
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.3f", value)
    }

    private enum InspectorTab: CaseIterable {
        case kuyu
        case manas

        var label: String {
            switch self {
            case .kuyu:
                return "Kuyu"
            case .manas:
                return "Manas"
            }
        }
    }
}

private struct ManasSignalFlowDiagram: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FlowNode(label: "Sensors")
                FlowArrow()
                FlowNode(label: "NerveBundle")
                FlowArrow()
                FlowNode(label: "Gating")
                FlowArrow()
                FlowNode(label: "Trunks")
                FlowArrow()
                FlowNode(label: "Core + Reflex")
                FlowArrow()
                FlowNode(label: "MotorNerve")
                FlowArrow()
                FlowNode(label: "Actuators")
                FlowArrow()
                FlowNode(label: "Plant")
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlowNode: View {
    let label: String

    var body: some View {
        Text(label)
            .font(KuyuUITheme.monoFont(size: 9))
            .foregroundStyle(KuyuUITheme.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(KuyuUITheme.background.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(KuyuUITheme.textSecondary.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct FlowArrow: View {
    var body: some View {
        Text("→")
            .font(KuyuUITheme.monoFont(size: 10))
            .foregroundStyle(KuyuUITheme.textSecondary)
            .padding(.horizontal, 2)
    }
}

private struct TrainingStatLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(KuyuUITheme.bodyFont(size: 11))
                .foregroundStyle(KuyuUITheme.textSecondary)
            Spacer()
            Text(value)
                .font(KuyuUITheme.monoFont(size: 11))
                .foregroundStyle(KuyuUITheme.textPrimary)
        }
    }
}

private struct ActuatorSignalsPanel: View {
    @Bindable var model: SimulationViewModel
    @State private var viewMode: ActuatorViewMode = .motorNerve

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kuyu Actuators")
                .font(KuyuUITheme.titleFont(size: 13))
                .foregroundStyle(KuyuUITheme.textPrimary)
            Picker("Actuator View", selection: $viewMode) {
                ForEach(ActuatorViewMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewMode) { _, mode in
                model.emitUIAction(level: .info, message: "Actuator view mode changed", action: "setActuatorViewMode", metadata: [
                    "mode": mode.label
                ])
            }
            VStack(spacing: 6) {
                switch viewMode {
                case .motorNerve:
                    if motorNerveOutputs.isEmpty {
                        Text("No MotorNerve output")
                            .font(KuyuUITheme.bodyFont(size: 11))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    } else {
                        ForEach(Array(motorNerveOutputs.enumerated()), id: \.offset) { index, output in
                            let definition = index < actuatorDefinitions.count ? actuatorDefinitions[index] : nil
                            let label = definition.map { "\($0.name) [\($0.units)]" } ?? "u\(index)"
                            let maxValue = definition.map { maxRangeValue(for: $0) } ?? motorNerveMaxValue
                            SignalBar(
                                label: label,
                                value: output,
                                displayValue: output,
                                maxValue: maxValue
                            )
                        }
                    }
                case .motor:
                    if !actuatorChannels.isEmpty {
                        ForEach(actuatorChannels, id: \.id) { channel in
                            let definition = actuatorDefinitions.first { $0.id == channel.id }
                            let label = definition.map { "\($0.name) [\($0.units)]" } ?? channel.id
                            let maxValue = definition.map { maxRangeValue(for: $0) } ?? actuatorMaxValue
                            SignalBar(
                                label: label,
                                value: channel.value,
                                displayValue: channel.value,
                                maxValue: maxValue
                            )
                        }
                    } else if !sortedActuatorValues.isEmpty {
                        ForEach(sortedActuatorValues, id: \.index.rawValue) { command in
                            let index = Int(command.index.rawValue)
                            let definition = index < actuatorDefinitions.count ? actuatorDefinitions[index] : nil
                            let label = definition.map { "\($0.name) [\($0.units)]" } ?? "A\(command.index.rawValue)"
                            let maxValue = definition.map { maxRangeValue(for: $0) } ?? actuatorMaxValue
                            SignalBar(
                                label: label,
                                value: command.value,
                                displayValue: command.value,
                                maxValue: maxValue
                            )
                        }
                    } else {
                        Text("No actuator output")
                            .font(KuyuUITheme.bodyFont(size: 11))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    }
                }
            }
        }
        .padding(10)
        .background(KuyuUITheme.panelHighlight.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var sortedActuatorValues: [ActuatorValue] {
        model.lastActuatorValues.sorted { $0.index.rawValue < $1.index.rawValue }
    }

    private var actuatorChannels: [ActuatorChannelSnapshot] {
        model.lastActuatorTelemetry?.channels ?? []
    }

    private var actuatorMaxValue: Double {
        let values = actuatorChannels.isEmpty
            ? sortedActuatorValues.map(\.value)
            : actuatorChannels.map(\.value)
        return max(values.max() ?? 0.0, 1.0)
    }

    private var motorNerveOutputs: [Double] {
        model.lastMotorNerveTrace?.uOut ?? []
    }

    private var motorNerveMaxValue: Double {
        max(motorNerveOutputs.max() ?? 0.0, 1.0)
    }

    private var actuatorDefinitions: [RobotDescriptor.SignalDefinition] {
        model.actuatorSignalDefinitions()
    }

    private func maxRangeValue(for definition: RobotDescriptor.SignalDefinition) -> Double {
        if let range = definition.range {
            return max(abs(range.min), abs(range.max), 1.0)
        }
        return actuatorMaxValue
    }

    private enum ActuatorViewMode: CaseIterable {
        case motorNerve
        case motor

        var label: String {
            switch self {
            case .motorNerve:
                return "MotorNerve u_out"
            case .motor:
                return "Actuator Output"
            }
        }
    }
}

private struct SensorSignalsPanel: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sensor Signals")
                .font(KuyuUITheme.titleFont(size: 13))
                .foregroundStyle(KuyuUITheme.textPrimary)
            VStack(spacing: 6) {
                if sensorDefinitions.isEmpty {
                    if model.lastSensorSamples.isEmpty {
                        Text("No sensor samples")
                            .font(KuyuUITheme.bodyFont(size: 11))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    } else {
                        ForEach(sortedSamples, id: \.channelIndex) { sample in
                            SignalBar(
                                label: "S\(sample.channelIndex)",
                                value: sample.value,
                                displayValue: sample.value,
                                maxValue: maxSampleValue
                            )
                        }
                    }
                } else {
                    ForEach(sensorDefinitions, id: \.id) { definition in
                        if let sample = sampleByIndex[UInt32(definition.index)] {
                            SignalBar(
                                label: "\(definition.name) [\(definition.units)]",
                                value: sample.value,
                                displayValue: sample.value,
                                maxValue: maxRangeValue(for: definition)
                            )
                        } else {
                            MissingSignalRow(label: "\(definition.name) [\(definition.units)]")
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(KuyuUITheme.panelHighlight.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var sensorDefinitions: [RobotDescriptor.SignalDefinition] {
        let definitions = model.currentDescriptor()?.signals.sensor ?? []
        return definitions.sorted { $0.index < $1.index }
    }

    private var sampleByIndex: [UInt32: ChannelSample] {
        Dictionary(uniqueKeysWithValues: model.lastSensorSamples.map { ($0.channelIndex, $0) })
    }

    private var sortedSamples: [ChannelSample] {
        model.lastSensorSamples.sorted { $0.channelIndex < $1.channelIndex }
    }

    private var maxSampleValue: Double {
        let values = model.lastSensorSamples.map(\.value)
        return max(values.max() ?? 0.0, 1.0)
    }

    private func maxRangeValue(for definition: RobotDescriptor.SignalDefinition) -> Double {
        if let range = definition.range {
            return max(abs(range.min), abs(range.max), 1.0)
        }
        return maxSampleValue
    }
}

private struct ManasSignalsPanel: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manas Signals")
                .font(KuyuUITheme.titleFont(size: 13))
                .foregroundStyle(KuyuUITheme.textPrimary)
            VStack(spacing: 6) {
                if sortedDriveIntents.isEmpty {
                    Text("No drive intents")
                        .font(KuyuUITheme.bodyFont(size: 11))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                } else {
                    ForEach(sortedDriveIntents, id: \.index.rawValue) { intent in
                        let definition = driveDefinitions[safe: Int(intent.index.rawValue)]
                        let label = definition.map { "\($0.name) [\($0.units)]" } ?? "Drive \(intent.index.rawValue)"
                        let maxValue = definition.map { maxRangeValue(for: $0) } ?? driveMaxValue
                        SignalBar(
                            label: label,
                            value: intent.activation,
                            displayValue: intent.activation,
                            maxValue: maxValue
                        )
                    }
                }
            }
            reflexSection
        }
        .padding(10)
        .background(KuyuUITheme.panelHighlight.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var sortedDriveIntents: [DriveIntent] {
        model.lastDriveIntents.sorted { $0.index.rawValue < $1.index.rawValue }
    }

    private var reflexSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reflex Corrections")
                .font(KuyuUITheme.titleFont(size: 12))
                .foregroundStyle(KuyuUITheme.textSecondary)
            if sortedReflexCorrections.isEmpty {
                Text("No reflex corrections")
                    .font(KuyuUITheme.bodyFont(size: 11))
                    .foregroundStyle(KuyuUITheme.textSecondary)
            } else {
                ForEach(sortedReflexCorrections, id: \.driveIndex.rawValue) { correction in
                    let definition = reflexDefinitions[safe: Int(correction.driveIndex.rawValue)]
                    let label = definition.map { $0.name } ?? "D\(correction.driveIndex.rawValue)"
                    HStack(spacing: 8) {
                        Text(label)
                            .font(KuyuUITheme.monoFont(size: 10))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                            .frame(minWidth: 24, alignment: .leading)
                        Text(String(format: "Δ %.3f", correction.delta))
                            .font(KuyuUITheme.monoFont(size: 10))
                            .foregroundStyle(KuyuUITheme.textPrimary)
                        Text(String(format: "Clamp %.2f", correction.clampMultiplier))
                            .font(KuyuUITheme.monoFont(size: 10))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                        Text(String(format: "Damp %.2f", correction.damping))
                            .font(KuyuUITheme.monoFont(size: 10))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    }
                }
            }
        }
    }

    private var sortedReflexCorrections: [ReflexCorrection] {
        model.lastReflexCorrections.sorted { $0.driveIndex.rawValue < $1.driveIndex.rawValue }
    }

    private var driveDefinitions: [RobotDescriptor.SignalDefinition] {
        model.driveSignalDefinitions()
    }

    private var reflexDefinitions: [RobotDescriptor.SignalDefinition] {
        model.reflexSignalDefinitions()
    }

    private var driveMaxValue: Double {
        let values = sortedDriveIntents.map(\.activation)
        return max(values.max() ?? 0.0, 1.0)
    }

    private func maxRangeValue(for definition: RobotDescriptor.SignalDefinition) -> Double {
        if let range = definition.range {
            return max(abs(range.min), abs(range.max), 1.0)
        }
        return driveMaxValue
    }
}

private struct MotorNerveChainPanel: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MotorNerve Chain")
                .font(KuyuUITheme.titleFont(size: 13))
                .foregroundStyle(KuyuUITheme.textPrimary)
            if stages.isEmpty {
                Text("No MotorNerve stages")
                    .font(KuyuUITheme.bodyFont(size: 11))
                    .foregroundStyle(KuyuUITheme.textSecondary)
            } else {
                ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(stage.id) [\(stage.type.rawValue)]")
                            .font(KuyuUITheme.monoFont(size: 10))
                            .foregroundStyle(KuyuUITheme.textPrimary)
                        Text("in: \(stage.inputs.map(signalLabel).joined(separator: ", "))")
                            .font(KuyuUITheme.monoFont(size: 9))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                        Text("out: \(stage.outputs.map(signalLabel).joined(separator: ", "))")
                            .font(KuyuUITheme.monoFont(size: 9))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    }
                    .padding(.vertical, 4)
                    if stage.id != stages.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .padding(10)
        .background(KuyuUITheme.panelHighlight.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var stages: [RobotDescriptor.MotorNerveStage] {
        model.motorNerveStages()
    }

    private var signalMap: [String: RobotDescriptor.SignalDefinition] {
        guard let descriptor = model.currentDescriptor() else { return [:] }
        let allSignals = descriptor.signals.sensor
            + descriptor.signals.drive
            + descriptor.signals.reflex
            + descriptor.signals.actuator
            + (descriptor.signals.motorNerve ?? [])
        return Dictionary(uniqueKeysWithValues: allSignals.map { ($0.id, $0) })
    }

    private func signalLabel(_ id: String) -> String {
        if let definition = signalMap[id] {
            return definition.name
        }
        return id
    }
}

private struct SignalBar: View {
    let label: String
    let value: Double
    let displayValue: Double
    let maxValue: Double

    init(label: String, value: Double, displayValue: Double? = nil, maxValue: Double = 1.0) {
        self.label = label
        self.value = value
        self.displayValue = displayValue ?? value
        self.maxValue = maxValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(KuyuUITheme.monoFont(size: 10))
                    .foregroundStyle(KuyuUITheme.textSecondary)
                Spacer()
                Text(String(format: "%.3f", displayValue))
                    .font(KuyuUITheme.monoFont(size: 10))
                    .foregroundStyle(KuyuUITheme.textPrimary)
            }
            ProgressView(value: clamp(value), total: maxValue)
                .tint(KuyuUITheme.accent)
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), maxValue)
    }
}

private struct MissingSignalRow: View {
    let label: String

    var body: some View {
        HStack {
            Text(label)
                .font(KuyuUITheme.monoFont(size: 10))
                .foregroundStyle(KuyuUITheme.textSecondary)
            Spacer()
            Text("missing")
                .font(KuyuUITheme.monoFont(size: 10))
                .foregroundStyle(KuyuUITheme.warning)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

private struct ManualActuatorControlPanel: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Manual Actuator Override")
                    .font(KuyuUITheme.titleFont(size: 13))
                    .foregroundStyle(KuyuUITheme.textPrimary)
                Spacer()
                Toggle("", isOn: $model.manualActuatorEnabled)
                    .labelsHidden()
            }
            Text("Forces baseline controller during single runs")
                .font(KuyuUITheme.bodyFont(size: 11))
                .foregroundStyle(KuyuUITheme.textSecondary)
            Toggle("Link all actuators", isOn: $model.manualActuatorLinked)
                .font(KuyuUITheme.bodyFont(size: 11))
                .foregroundStyle(KuyuUITheme.textSecondary)
                .toggleStyle(.switch)

            Group {
                if model.manualActuatorLinked {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Linked ratio")
                                .font(KuyuUITheme.monoFont(size: 10))
                                .foregroundStyle(KuyuUITheme.textSecondary)
                            Spacer()
                            Text(String(format: "%.0f%%", model.manualActuatorMaster * 100.0))
                                .font(KuyuUITheme.monoFont(size: 10))
                                .foregroundStyle(KuyuUITheme.textPrimary)
                        }
                        Slider(value: $model.manualActuatorMaster, in: 0.0...1.0)
                        if !linkedPreviewText.isEmpty {
                            Text(linkedPreviewText)
                                .font(KuyuUITheme.monoFont(size: 10))
                                .foregroundStyle(KuyuUITheme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(actuatorLabels.enumerated()), id: \.offset) { index, label in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(labelWithUnit(for: index, label: label))
                                        .font(KuyuUITheme.monoFont(size: 10))
                                        .foregroundStyle(KuyuUITheme.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(formattedValue(for: index))
                                        .font(KuyuUITheme.monoFont(size: 10))
                                        .foregroundStyle(KuyuUITheme.textPrimary)
                                }
                                Slider(value: binding(for: index), in: range(for: index))
                                HStack {
                                    Text(formattedRangeBound(range(for: index).lowerBound, unit: unit(for: index)))
                                    Spacer()
                                    Text(formattedRangeBound(range(for: index).upperBound, unit: unit(for: index)))
                                }
                                .font(KuyuUITheme.monoFont(size: 9))
                                .foregroundStyle(KuyuUITheme.textSecondary)
                            }
                        }
                    }
                }
            }
            .disabled(!model.manualActuatorEnabled)
        }
        .padding(10)
        .background(KuyuUITheme.panelHighlight.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var actuatorLabels: [String] {
        model.manualActuatorChannelLabels()
    }

    private var linkedPreviewText: String {
        actuatorLabels.enumerated().map { index, label in
            let physical = model.manualActuatorValuePhysical(index: index)
            let unit = unit(for: index)
            return "\(label): \(formattedNumber(physical))\(unitSuffix(unit))"
        }.joined(separator: "  ")
    }

    private func binding(for index: Int) -> Binding<Double> {
        Binding(
            get: {
                value(for: index)
            },
            set: { value in
                model.setManualActuatorValuePhysical(index: index, value: value)
            }
        )
    }

    private func value(for index: Int) -> Double {
        model.manualActuatorValuePhysical(index: index)
    }

    private func range(for index: Int) -> ClosedRange<Double> {
        model.manualActuatorPhysicalRange(index: index)
    }

    private func unit(for index: Int) -> String {
        model.manualActuatorChannelUnit(index: index)
    }

    private func formattedValue(for index: Int) -> String {
        let value = model.manualActuatorValuePhysical(index: index)
        return "\(formattedNumber(value))\(unitSuffix(unit(for: index)))"
    }

    private func labelWithUnit(for index: Int, label: String) -> String {
        let unit = unit(for: index)
        if unit.isEmpty {
            return label
        }
        return "\(label) [\(unit)]"
    }

    private func formattedRangeBound(_ value: Double, unit: String) -> String {
        "\(formattedNumber(value))\(unitSuffix(unit))"
    }

    private func formattedNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func unitSuffix(_ unit: String) -> String {
        unit.isEmpty ? "" : " \(unit)"
    }
}

private struct TrainingChartsGrid: View {
    @Bindable var model: SimulationViewModel

    private let columns = [
        GridItem(.flexible(minimum: 220), spacing: 12),
        GridItem(.flexible(minimum: 220), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                MetricChartView(
                    title: "Supervised Loss",
                    unit: "loss",
                    samples: model.trainingLossSamples,
                    lineColor: KuyuUITheme.accent
                )
                MetricChartView(
                    title: "Loop Score",
                    unit: "score",
                    samples: model.loopScoreSamples,
                    lineColor: KuyuUITheme.success
                )
                MetricChartView(
                    title: "Worst Overshoot",
                    unit: "deg",
                    samples: model.overshootSamples,
                    lineColor: KuyuUITheme.warning
                )
                MetricChartView(
                    title: "Recovery Time",
                    unit: "sec",
                    samples: model.recoverySamples,
                    lineColor: KuyuUITheme.accent
                )
                MetricChartView(
                    title: "HF Stability",
                    unit: "score",
                    samples: model.hfSamples,
                    lineColor: KuyuUITheme.success
                )
            }
            .padding(12)
        }
    }
}

#Preview {
    let buffer = UILoggingBootstrap.buffer
    let logStore = UILogStore(buffer: buffer)
    let model = SimulationViewModel(logStore: logStore)
    TrainingDashboardView(
        model: model,
        roll: 0.1,
        pitch: -0.2,
        yaw: 0.3,
        position: Axis3(x: 0, y: 0, z: 0),
        renderInfo: nil
    )
    .frame(width: 1200, height: 800)
}
