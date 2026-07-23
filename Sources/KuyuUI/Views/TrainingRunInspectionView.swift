import KuyuCore
import KuyuScenarios
import KuyuTraining
import Logging
import SwiftUI

#if os(macOS)
import AppKit
#endif

public struct TrainingRunInspectionView: View {
    public let artifact: TrainingRunInspectionArtifact

    @State private var selectedScenarioIdentity = ""
    @State private var sampleIndex = 0
    @State private var isPlaying = false
    @State private var isScenarioSelectorPresented = false
    @State private var copiedConstraintMessage: String?

    public init(
        artifact: TrainingRunInspectionArtifact,
        initialScenarioIdentity: String? = nil
    ) {
        self.artifact = artifact
        _selectedScenarioIdentity = State(initialValue: initialScenarioIdentity ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            header
            executionContractSummary
            HSplitView {
                WorldRealityView(
                    roll: eulerAngles.roll,
                    pitch: eulerAngles.pitch,
                    yaw: eulerAngles.yaw,
                    position: currentSample.step.plantState.root.position,
                    label: "\(selectedScenario.scenarioID) seed \(selectedScenario.seed)",
                    renderInfo: nil,
                    actuatorChannels: currentSample.step.actuatorTelemetry.channels,
                    renderingMode: .staticFallback
                )
                .frame(minWidth: 460, maxWidth: .infinity, minHeight: 470)

                metricCharts
                    .frame(minWidth: 430, maxWidth: .infinity, minHeight: 470)
            }
            playbackControls
        }
        .onAppear {
            selectInitialScenarioIfNeeded()
        }
        .onChange(of: selectedScenarioIdentity) { _, _ in
            sampleIndex = 0
            isPlaying = false
        }
        .task(id: isPlaying) {
            guard isPlaying else { return }
            while isPlaying, !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
                if sampleIndex + 1 < selectedScenario.samples.count {
                    sampleIndex += 1
                } else {
                    isPlaying = false
                }
            }
        }
    }

    private var executionContractSummary: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack(spacing: KuyuSpacing.md) {
                Label(artifact.profile.profileID, systemImage: "doc.text.magnifyingglass")
                Label(artifact.execution.actionContractSchemaID, systemImage: "point.3.connected.trianglepath.dotted")
                Label(actionRealizationSummary, systemImage: "gyroscope")
                if let iteration = artifact.iteration {
                    Label("iteration \(iteration)", systemImage: "arrow.triangle.2.circlepath")
                }
                if let descriptor = artifact.safetyCostDescriptor {
                    Label(
                        "\(descriptor.id) v\(descriptor.version)",
                        systemImage: "shield.lefthalf.filled"
                    )
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: KuyuSpacing.md) {
                Label(artifact.execution.robotManifestID ?? "reference baseline", systemImage: "cpu")
                Label(
                    String(
                        format: "max %.3g N · tau %.3g s",
                        artifact.execution.parameters.maxThrust,
                        artifact.execution.parameters.motorTimeConstant
                    ),
                    systemImage: "fan"
                )
                Label(
                    String(
                        format: "rate %.3g /s",
                        artifact.execution.motorNerveSettings.rateLimitPerSecond
                    ),
                    systemImage: "gauge.with.dots.needle.67percent"
                )
                Label(smoothingSummary, systemImage: "waveform.path")
                Label(
                    String(
                        format: "dt %.4g s · cut %llu",
                        selectedScenario.sourcePhysicsTimeStep,
                        selectedScenario.sourceControlPeriodSteps
                    ),
                    systemImage: "timer"
                )
                Text(selectedScenario.configHash)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
                Spacer(minLength: 0)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
    }

    private var header: some View {
        HStack(spacing: KuyuSpacing.sm) {
            Label("Checkpoint Replay", systemImage: "cube.transparent")
                .font(.headline)
            Button {
                isPlaying = false
                isScenarioSelectorPresented.toggle()
                logScenarioSelector(
                    action: isScenarioSelectorPresented
                        ? "openScenarioSelector"
                        : "closeScenarioSelector"
                )
            } label: {
                HStack(spacing: KuyuSpacing.xs) {
                    Text("\(selectedScenario.scenarioID) · \(selectedScenario.seed)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: KuyuSpacing.sm)
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .frame(width: 320)
            .accessibilityLabel("Scenario")
            .accessibilityValue("\(selectedScenario.scenarioID), seed \(selectedScenario.seed)")
            .popover(isPresented: $isScenarioSelectorPresented, arrowEdge: .top) {
                scenarioSelector
            }
            StatBadgeView(passed: selectedScenario.passed)
            if let failureReason = selectedScenario.failureReason {
                Label(failureReason, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            Text(artifact.origin == .derivedReevaluation ? "derived re-evaluation" : "iteration evidence")
                .font(.caption)
                .foregroundStyle(artifact.origin == .derivedReevaluation ? .orange : .secondary)
            Text(artifact.checkpointRole.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(artifact.checkpointPath)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 360)
        }
    }

    private var scenarioSelector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: KuyuSpacing.xs) {
                Label("Scenarios", systemImage: "list.bullet")
                    .font(.headline)
                Spacer(minLength: KuyuSpacing.sm)
                Text("\(artifact.scenarios.count)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, KuyuSpacing.sm)
            .padding(.vertical, KuyuSpacing.xs)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(artifact.scenarios, id: \.identity) { scenario in
                        Button {
                            selectScenario(scenario)
                        } label: {
                            HStack(spacing: KuyuSpacing.sm) {
                                Image(
                                    systemName: scenario.identity == selectedScenarioIdentity
                                        ? "checkmark"
                                        : "circle"
                                )
                                .foregroundStyle(
                                    scenario.identity == selectedScenarioIdentity
                                        ? Color.accentColor
                                        : Color.clear
                                )
                                .frame(width: 16, height: 16)

                                Text("\(scenario.scenarioID) · \(scenario.seed)")
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)

                                Spacer(minLength: KuyuSpacing.sm)

                                Image(
                                    systemName: scenario.passed
                                        ? "checkmark.circle.fill"
                                        : "xmark.octagon.fill"
                                )
                                .foregroundStyle(scenario.passed ? .green : .red)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, KuyuSpacing.sm)
                            .frame(height: 32)
                            .background {
                                if scenario.identity == selectedScenarioIdentity {
                                    Color.accentColor.opacity(0.12)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(
            width: 340,
            height: min(440, 49 + CGFloat(artifact.scenarios.count * 32))
        )
    }

    private var metricCharts: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 190), spacing: KuyuSpacing.sm),
                    GridItem(.flexible(minimum: 190), spacing: KuyuSpacing.sm),
                ],
                spacing: KuyuSpacing.sm
            ) {
                MetricChartView(
                    title: "Tilt",
                    unit: "rad",
                    samples: metricSamples { $0.step.safetyTrace.tiltRadians },
                    lineColor: .cyan
                )
                MetricChartView(
                    title: "Omega",
                    unit: "rad/s",
                    samples: metricSamples { $0.step.safetyTrace.omegaMagnitude },
                    lineColor: .red
                )
                MetricChartView(
                    title: "Altitude",
                    unit: "m",
                    samples: metricSamples { $0.step.plantState.root.position.z },
                    lineColor: .green
                )
                MetricChartView(
                    title: "Safety cost",
                    unit: "cost",
                    samples: metricSamples { $0.safetyCost },
                    lineColor: .purple
                )
            }
            .padding(.trailing, KuyuSpacing.xs)
        }
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack(spacing: KuyuSpacing.sm) {
                HStack(spacing: KuyuSpacing.xs) {
                    Button {
                        sampleIndex = max(0, sampleIndex - 1)
                        isPlaying = false
                    } label: {
                        Image(systemName: "backward.frame.fill")
                            .frame(width: 18, height: 18)
                    }
                    .help("Previous sample")

                    Button {
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 18, height: 18)
                    }
                    .help(isPlaying ? "Pause" : "Play")

                    Button {
                        sampleIndex = min(selectedScenario.samples.count - 1, sampleIndex + 1)
                        isPlaying = false
                    } label: {
                        Image(systemName: "forward.frame.fill")
                            .frame(width: 18, height: 18)
                    }
                    .help("Next sample")
                }
                .fixedSize(horizontal: true, vertical: false)

                Slider(
                    value: Binding(
                        get: { Double(sampleIndex) },
                        set: { sampleIndex = Int($0.rounded()) }
                    ),
                    in: 0...Double(max(0, selectedScenario.samples.count - 1)),
                    step: 1
                )
                .frame(minWidth: 240, maxWidth: .infinity)
                .layoutPriority(1)

                Text(String(format: "t %.3fs", currentSample.step.time.time))
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: 92, alignment: .trailing)

                Text("\(sampleIndex + 1)/\(selectedScenario.samples.count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .trailing)
            }

            constraintStatus
        }
        .buttonStyle(.borderless)
    }

    private var constraintStatus: some View {
        let violationIDs = currentSample.constraintViolationIDs
        let message = violationIDs.joined(separator: ", ")

        return HStack(spacing: KuyuSpacing.xs) {
            if violationIDs.isEmpty {
                Label("No active constraint violation", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            } else {
                Label {
                    Text(message)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
                .help(message)

                Button {
                    copyConstraintViolations(message)
                } label: {
                    Image(
                        systemName: copiedConstraintMessage == message
                            ? "checkmark"
                            : "doc.on.doc"
                    )
                    .frame(width: 18, height: 18)
                }
                .accessibilityLabel("Copy constraint violations")
                .help(copiedConstraintMessage == message ? "Copied" : "Copy all violations")
            }
            Spacer(minLength: 0)
        }
        .font(.system(.caption2, design: .monospaced))
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
    }

    private func copyConstraintViolations(_ message: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setString(
            currentSample.constraintViolationIDs.joined(separator: "\n"),
            forType: .string
        )
        logConstraintCopy(succeeded: copied)
        guard copied else { return }

        copiedConstraintMessage = message
        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard copiedConstraintMessage == message else { return }
            copiedConstraintMessage = nil
        }
        #endif
    }

    private func logConstraintCopy(succeeded: Bool) {
        let logger = Logger(label: "kuyu.ui")
        let metadata: Logger.Metadata = [
            "action": "copyConstraintViolationIDs",
            "task": .string(artifact.profile.task),
            "scenarioID": .string(selectedScenario.scenarioID),
            "seed": .stringConvertible(selectedScenario.seed),
            "stepIndex": .stringConvertible(currentSample.step.time.stepIndex),
            "violationCount": .stringConvertible(currentSample.constraintViolationIDs.count),
        ]
        if succeeded {
            logger.info("Constraint violation identifiers copied", metadata: metadata)
        } else {
            logger.error("Constraint violation identifiers could not be copied", metadata: metadata)
        }
    }

    private func selectScenario(_ scenario: TrainingRunInspectionArtifact.Scenario) {
        selectedScenarioIdentity = scenario.identity
        isScenarioSelectorPresented = false

        let logger = Logger(label: "kuyu.ui")
        logger.info("Training inspection scenario selected", metadata: [
            "action": "selectInspectionScenario",
            "task": .string(artifact.profile.task),
            "scenarioID": .string(scenario.scenarioID),
            "seed": .stringConvertible(scenario.seed),
        ])
    }

    private func logScenarioSelector(action: String) {
        let logger = Logger(label: "kuyu.ui")
        logger.info("Training inspection scenario selector changed", metadata: [
            "action": .string(action),
            "task": .string(artifact.profile.task),
            "scenarioID": .string(selectedScenario.scenarioID),
            "seed": .stringConvertible(selectedScenario.seed),
        ])
    }

    private var selectedScenario: TrainingRunInspectionArtifact.Scenario {
        artifact.scenarios.first { $0.identity == selectedScenarioIdentity }
            ?? artifact.scenarios[0]
    }

    private var currentSample: TrainingRunInspectionArtifact.Sample {
        let index = min(max(sampleIndex, 0), selectedScenario.samples.count - 1)
        return selectedScenario.samples[index]
    }

    private var eulerAngles: (roll: Double, pitch: Double, yaw: Double) {
        let quaternion = currentSample.step.plantState.root.orientation
        let sinr = 2 * (quaternion.w * quaternion.x + quaternion.y * quaternion.z)
        let cosr = 1 - 2 * (quaternion.x * quaternion.x + quaternion.y * quaternion.y)
        let roll = atan2(sinr, cosr)
        let sinp = 2 * (quaternion.w * quaternion.y - quaternion.z * quaternion.x)
        let pitch = abs(sinp) >= 1
            ? (Double.pi / 2) * (sinp > 0 ? 1 : -1)
            : asin(sinp)
        let siny = 2 * (quaternion.w * quaternion.z + quaternion.x * quaternion.y)
        let cosy = 1 - 2 * (quaternion.y * quaternion.y + quaternion.z * quaternion.z)
        return (roll, pitch, atan2(siny, cosy))
    }

    private var smoothingSummary: String {
        guard let smoothing = artifact.execution.motorNerveSettings.smoothingTimeConstant else {
            return "smoothing none"
        }
        return String(format: "smoothing %.3g s", smoothing)
    }

    private var actionRealizationSummary: String {
        switch artifact.execution.actionRealization {
        case .driveMixer:
            return "drive mixer"
        case .temporalCTBR(let config):
            return String(
                format: "CTBR rates %.3g/%.3g/%.3g",
                config.bodyRateScale.x,
                config.bodyRateScale.y,
                config.bodyRateScale.z
            )
        }
    }

    private func metricSamples(
        value: (TrainingRunInspectionArtifact.Sample) -> Double?
    ) -> [MetricSample] {
        selectedScenario.samples.compactMap { sample in
            value(sample).map { MetricSample(time: sample.step.time.time, value: $0) }
        }
    }

    private func selectInitialScenarioIfNeeded() {
        guard selectedScenarioIdentity.isEmpty else { return }
        selectedScenarioIdentity = artifact.scenarios.first(where: { !$0.passed })?.identity
            ?? artifact.scenarios[0].identity
    }
}
