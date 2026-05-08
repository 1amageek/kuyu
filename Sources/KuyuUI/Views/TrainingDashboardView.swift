import SwiftUI
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public struct TrainingDashboardView: View {
    @Bindable var model: SimulationViewModel
    let roll: Double
    let pitch: Double
    let yaw: Double
    let position: Axis3
    let renderInfo: RenderAssetInfo?

    @SceneStorage("trainingBottomTab") private var bottomTab: BottomTab = .events

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
        LearningStudioDashboardView(
            model: model,
            roll: roll,
            pitch: pitch,
            yaw: yaw,
            position: position,
            renderInfo: renderInfo
        )
    }

    @ViewBuilder
    private var mainCanvas: some View {
        VStack(spacing: 0) {
            TrainingStatusBanner(model: model)
                .padding(.horizontal, KuyuSpacing.md)
                .padding(.vertical, KuyuSpacing.sm)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                TrainingWorldColumn(
                    roll: roll,
                    pitch: pitch,
                    yaw: yaw,
                    position: position,
                    renderInfo: renderInfo
                )
                .frame(
                    minWidth: KuyuLayout.realityMinWidth,
                    idealWidth: 420,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )

                Divider()

                TrainingLearningColumn(model: model)
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                TrainingDecisionColumn(model: model)
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var bottomDrawer: some View {
        VStack(spacing: 0) {
            bottomTabBar
            Group {
                switch bottomTab {
                case .events:
                    TrainingEventsView(model: model)
                case .generations:
                    TrainingGenerationsView(model: model)
                case .artifacts:
                    TrainingArtifactsView(model: model)
                case .signals:
                    LiveSignalsColumn(model: model)
                case .log:
                    LogConsoleView(
                        entries: model.logStore.entries,
                        onClear: model.logStore.clear
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var bottomTabBar: some View {
        HStack(spacing: KuyuSpacing.sm) {
            Picker("Bottom Pane", selection: $bottomTab) {
                ForEach(BottomTab.allCases, id: \.self) { tab in
                    Label(tab.label, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 520)
            Spacer()
        }
        .padding(.horizontal, KuyuSpacing.md)
        .padding(.vertical, KuyuSpacing.xs)
        .background(.bar)
    }

    private enum BottomTab: String, CaseIterable {
        case events = "timeline"
        case generations
        case artifacts
        case signals
        case log

        var label: String {
            switch self {
            case .events: return "Events"
            case .generations: return "Generations"
            case .artifacts: return "Artifacts"
            case .signals: return "Signals"
            case .log: return "Log"
            }
        }

        var systemImage: String {
            switch self {
            case .events: return "clock"
            case .generations: return "chart.line.uptrend.xyaxis"
            case .artifacts: return "folder"
            case .signals: return "waveform.path"
            case .log: return "terminal"
            }
        }
    }
}

// MARK: - Dashboard Columns

private struct TrainingWorldColumn: View {
    let roll: Double
    let pitch: Double
    let yaw: Double
    let position: Axis3
    let renderInfo: RenderAssetInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            DashboardSectionHeader(
                title: "World",
                subtitle: renderInfo?.name ?? "Robot proxy"
            )

            WorldRealityView(
                roll: roll,
                pitch: pitch,
                yaw: yaw,
                position: position,
                label: renderInfo?.name ?? "Robot proxy",
                renderInfo: renderInfo
            )
            .frame(minHeight: 320, maxHeight: .infinity)

            WorldStateView(
                roll: roll,
                pitch: pitch,
                yaw: yaw,
                position: position
            )
        }
        .padding(KuyuSpacing.sm)
    }
}

private struct TrainingLearningColumn: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            DashboardSectionHeader(
                title: "Learning",
                subtitle: "Loss, reward, quality, and worker throughput"
            )

            TrainingChartsGrid(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(KuyuSpacing.sm)
    }
}

private struct TrainingDecisionColumn: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                DashboardSectionHeader(
                    title: "Decision",
                    subtitle: "Current health, acceptance gate, and campaign state"
                )
                TrainingReadinessView(model: model)
                TrainingLiveHealthView(model: model)
                TrainingAcceptanceGateView(model: model)
                PostRegressionGateView(model: model)
                LearningCampaignView(model: model)
            }
            .padding(KuyuSpacing.sm)
        }
    }
}

private struct DashboardSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorldStateView: View {
    let roll: Double
    let pitch: Double
    let yaw: Double
    let position: Axis3

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                StatRow(label: "Position", value: positionText)
                StatRow(label: "Roll", value: angleText(roll))
                StatRow(label: "Pitch", value: angleText(pitch))
                StatRow(label: "Yaw", value: angleText(yaw))
            }
        } label: {
            Label("Robot State", systemImage: "cube.transparent")
        }
    }

    private var positionText: String {
        String(format: "x %.2f  y %.2f  z %.2f", position.x, position.y, position.z)
    }

    private func angleText(_ value: Double) -> String {
        String(format: "%.2f rad", value)
    }
}

// MARK: - Status Banner

struct TrainingStatusBanner: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                HStack(spacing: KuyuSpacing.md) {
                    StatusPill(currentStatus, tone: statusTone)
                    Text(model.selectedModel?.name ?? "No model")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(model.taskMode.rawValue)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    PhaseBadge(phase: model.trainingLiveStatus.phase)
                }

                ProgressView(value: progressValue, total: progressTotal)
                    .progressViewStyle(.linear)

                HStack(spacing: KuyuSpacing.lg) {
                    bannerStat("Iter", value: "\(model.loopIteration)/\(model.loopMaxIterations)")
                    bannerStat("Best", value: format(model.loopBestScore))
                    bannerStat("Last", value: format(model.loopLastScore))
                    bannerStat("Loss", value: format(model.lastTrainingLoss))
                    bannerStat("Gate", value: gateText)
                    bannerStat("Campaign", value: campaignText)
                    Spacer()
                }
            }
        }
    }

    private func bannerStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private var currentStatus: String {
        if model.isTraining { return "training" }
        if model.isLoopRunning { return model.isLoopPaused ? "paused" : "running" }
        if model.isRunning { return "simulating" }
        return "idle"
    }

    private var statusTone: StatusPill.Tone {
        if model.isTraining || model.isLoopRunning {
            return model.isLoopPaused ? .warning : .info
        }
        if model.isRunning { return .info }
        return .neutral
    }

    private var gateText: String {
        if let accepted = model.lastPostRegressionGate?.accepted {
            return accepted ? "post accepted" : "post rejected"
        }
        if let accepted = model.trainingLiveStatus.convergenceAccepted {
            return accepted ? "accepted" : "rejected"
        }
        return "pending"
    }

    private var campaignText: String {
        if let state = model.learningCampaignState {
            return state.statusLabel
        }
        if model.learningCampaignMonitorEnabled {
            return "watching"
        }
        return "--"
    }

    private var progressValue: Double {
        Double(min(model.loopIteration, max(model.loopMaxIterations, 1)))
    }

    private var progressTotal: Double {
        Double(max(model.loopMaxIterations, 1))
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.4f", value)
    }
}

// MARK: - Live Signals Column

struct LiveSignalsColumn: View {
    @Bindable var model: SimulationViewModel
    @SceneStorage("liveSignalsTab") private var tab: SignalsTab = .kuyu

    private enum SignalsTab: String, CaseIterable {
        case kuyu
        case manas

        var label: String {
            switch self {
            case .kuyu: return "Kuyu"
            case .manas: return "Manas"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Signals", selection: $tab) {
                ForEach(SignalsTab.allCases, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, KuyuSpacing.sm)
            .padding(.vertical, KuyuSpacing.xs)
            .background(.bar)

            ScrollView {
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    switch tab {
                    case .kuyu:
                        SensorSignalsCard(model: model)
                        ActuatorSignalsCard(model: model)
                    case .manas:
                        ManasSignalsCard(model: model)
                    }
                }
                .padding(KuyuSpacing.sm)
            }
        }
    }
}

// MARK: - Charts Grid

struct TrainingChartsGrid: View {
    @Bindable var model: SimulationViewModel

    private let columns = [
        GridItem(.flexible(minimum: 220), spacing: KuyuSpacing.sm),
        GridItem(.flexible(minimum: 220), spacing: KuyuSpacing.sm)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: KuyuSpacing.sm) {
                MetricChartView(title: "Supervised Loss", unit: "loss", samples: model.trainingLossSamples, lineColor: .accentColor)
                MetricChartView(title: "Validation Loss", unit: "loss", samples: model.validationLossSamples, lineColor: .purple)
                MetricChartView(title: "Loop Score", unit: "score", samples: model.loopScoreSamples, lineColor: .green)
                MetricChartView(title: "Reward Average", unit: "reward", samples: model.rewardAverageSamples, lineColor: .mint)
                MetricChartView(title: "Pass Rate", unit: "0...1", samples: model.passRateSamples, lineColor: .green)
                MetricChartView(title: "Failure Rate", unit: "0...1", samples: model.failureRateSamples, lineColor: .orange)
                MetricChartView(title: "Safety Violation", unit: "sec", samples: model.safetyViolationSamples, lineColor: .red)
                MetricChartView(title: "Worker Throughput", unit: "items/sec", samples: model.workerThroughputSamples, lineColor: .blue)
                MetricChartView(title: "Worst Overshoot", unit: "deg", samples: model.overshootSamples, lineColor: .orange)
                MetricChartView(title: "Recovery Time", unit: "sec", samples: model.recoverySamples, lineColor: .accentColor)
                MetricChartView(title: "HF Stability", unit: "score", samples: model.hfSamples, lineColor: .green)
            }
            .padding(KuyuSpacing.sm)
        }
    }
}

// MARK: - Bottom Pane: Events

struct TrainingEventsView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                if model.trainingTimeline.isEmpty {
                    Text("No events yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(KuyuSpacing.md)
                } else {
                    ForEach(model.trainingTimeline) { entry in
                        HStack(spacing: KuyuSpacing.sm) {
                            PhaseDot(phase: entry.phase)
                            Text("i\(entry.iteration)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                            Text(entry.message)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer()
                        }
                    }
                }
            }
            .padding(KuyuSpacing.sm)
        }
    }
}

struct TrainingGenerationsView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                if let state = model.learningCampaignState {
                    generationHeader(state)
                    let rows = state.latestGenerations
                    if rows.isEmpty {
                        Text("No generation records yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(KuyuSpacing.md)
                    } else {
                        ForEach(rows) { row in
                            generationRow(row)
                        }
                    }
                } else {
                    Text("No campaign loaded")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(KuyuSpacing.md)
                }
            }
            .padding(KuyuSpacing.sm)
        }
    }

    private func generationHeader(_ state: LearningCampaignRunStoreState) -> some View {
        HStack(spacing: KuyuSpacing.lg) {
            StatusPill(state.statusLabel, tone: state.isActive ? .info : .neutral)
            StatRow(label: "Task", value: state.task, compact: true)
                .frame(width: 150)
            StatRow(label: "Accepted", value: "\(state.acceptedCount)/\(state.seedCount)", compact: true)
                .frame(width: 150)
            if let delta = state.bestDelta {
                StatRow(label: "Best Delta", value: String(format: "%+.3f", delta), compact: true)
                    .frame(width: 170)
            }
            Spacer()
        }
    }

    private func generationRow(_ row: LearningCampaignGenerationState) -> some View {
        GroupBox {
            HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.seed)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("generation \(row.generationIndex)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 120, alignment: .leading)

                StatusPill(row.accepted ? "accepted" : (row.incumbentImproved ? "improved" : "searching"), tone: row.accepted ? .success : (row.incumbentImproved ? .info : .neutral))

                StatRow(label: "Best", value: format(row.bestFitness), compact: true)
                    .frame(width: 120)
                StatRow(label: "Incumbent", value: format(row.incumbentFitness), compact: true)
                    .frame(width: 140)
                StatRow(label: "Delta", value: signed(row.bestVsIncumbentDelta), compact: true)
                    .frame(width: 120)
                StatRow(label: "Mutation", value: String(format: "%.3f", row.mutationRate), compact: true)
                    .frame(width: 130)

                if let candidate = row.bestCandidateID {
                    Text(candidate)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            if !row.rejectionReasons.isEmpty {
                Text(row.rejectionReasons.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.3f", value)
    }

    private func signed(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%+.3f", value)
    }
}

struct TrainingArtifactsView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                GroupBox {
                    VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                        artifactRow(label: "Configured Root", path: emptyToNil(model.learningCampaignArtifactDirectory))
                        artifactRow(label: "Loaded Root", path: model.learningCampaignState?.artifactDirectory.path)
                        artifactRow(label: "Final Checkpoint", path: model.learningCampaignState?.finalCheckpoint)
                        artifactRow(label: "Plan", path: artifactPath("learning-campaign-plan.json"))
                        artifactRow(label: "Status", path: artifactPath("campaign-status.json"))
                        artifactRow(label: "Summary", path: artifactPath("learning-campaign-summary.json"))
                        artifactRow(label: "Validation", path: artifactPath("learning-campaign-validation.json"))
                    }
                } label: {
                    Label("Campaign Artifacts", systemImage: "shippingbox")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                        artifactRow(label: "Training Run", path: model.trainingLiveStatus.artifactDirectoryPath)
                        artifactRow(label: "Post Regression", path: model.lastPostRegressionGate?.artifactDirectory.path)
                    }
                } label: {
                    Label("Gate Artifacts", systemImage: "doc.badge.gearshape")
                }
            }
            .padding(KuyuSpacing.sm)
        }
    }

    private func artifactRow(label: String, path: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(path ?? "--")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(path == nil ? .secondary : .primary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func artifactPath(_ fileName: String) -> String? {
        let root = model.learningCampaignState?.artifactDirectory
            ?? emptyToNil(model.learningCampaignArtifactDirectory).map { URL(fileURLWithPath: $0, isDirectory: true) }
        return root?.appendingPathComponent(fileName).path
    }
}

// MARK: - Views (used by Dashboard and Inspector)

struct TrainingReadinessView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                StatRow(label: "Source Checkpoint", value: sourceCheckpointText)
                StatRow(label: "Campaign Root", value: campaignRootText)
                StatRow(label: "Task", value: model.taskMode.rawValue)
                StatRow(label: "Model", value: model.selectedModel?.name ?? "--")
                if let error = model.learningCampaignError {
                    StatRow(label: "Issue", value: error, valueColor: .orange)
                }
            }
        } label: {
            HStack {
                Label("Readiness", systemImage: "checkmark.shield")
                Spacer()
                StatusPill(readinessLabel, tone: readinessTone)
            }
        }
    }

    private var sourceCheckpointText: String {
        let explicit = model.learningCampaignSourceCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return URL(fileURLWithPath: explicit).lastPathComponent }
        return model.selectedModel?.storageURL.lastPathComponent ?? "--"
    }

    private var campaignRootText: String {
        let path = model.learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? "--" : URL(fileURLWithPath: path).lastPathComponent
    }

    private var readinessLabel: String {
        let hasSource = !model.learningCampaignSourceCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || model.selectedModel != nil
        let hasRoot = !model.learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasSource && hasRoot ? "ready" : "incomplete"
    }

    private var readinessTone: StatusPill.Tone {
        readinessLabel == "ready" ? .success : .warning
    }
}

struct TrainingLiveHealthView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        let status = model.trainingLiveStatus
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                StatRow(label: "Phase", value: status.phase.rawValue)
                StatRow(label: "Dataset", value: datasetText)
                StatRow(label: "LR", value: format(status.learningRate, digits: 6))
                StatRow(label: "Epochs", value: status.epochs.map(String.init) ?? "--")
                Divider().opacity(0.4)
                QualityGauge(label: "Pass", value: status.passRate, tint: .green)
                QualityGauge(label: "Failure", value: status.failureRate, tint: .orange)
                StatRow(label: "Safety", value: safetyText)
            }
        } label: {
            Label("Live Health", systemImage: "waveform.path.ecg")
        }
    }

    private var datasetText: String {
        let status = model.trainingLiveStatus
        guard let count = status.datasetCount else {
            return status.datasetPath == nil ? "--" : "pending"
        }
        return "\(count)"
    }

    private var safetyText: String {
        guard let value = model.trainingLiveStatus.safetyViolationSeconds else { return "--" }
        return String(format: "%.3fs", value)
    }

    private func format(_ value: Double?, digits: Int = 3) -> String {
        guard let value else { return "--" }
        return String(format: "%.\(digits)f", value)
    }
}

struct TrainingAcceptanceGateView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        let status = model.trainingLiveStatus
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                StatRow(label: "Convergence", value: status.convergenceReason ?? "--")
                StatRow(label: "Checkpoint", value: checkpointText)
                StatRow(label: "Best", value: status.bestCheckpointID ?? "--")
                HStack(spacing: KuyuSpacing.xs) {
                    FlagBadge(label: "Plateau", active: status.plateauDetected)
                    FlagBadge(label: "Overfit", active: status.overfitRiskDetected)
                    FlagBadge(label: "Safety", active: status.safetyRegressionDetected)
                }
                if let artifactPath = status.artifactDirectoryPath {
                    Text(artifactPath)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } label: {
            HStack {
                Label("Acceptance Gate", systemImage: "checkmark.seal")
                Spacer()
                GateBadge(value: status.convergenceAccepted)
            }
        }
    }

    private var checkpointText: String {
        let status = model.trainingLiveStatus
        guard let state = status.checkpointState else { return "--" }
        if let reason = status.checkpointReason, reason != state {
            return "\(state) (\(reason))"
        }
        return state
    }
}

struct PostRegressionGateView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        let gate = model.lastPostRegressionGate
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                StatRow(label: "Quality Task", value: gate?.qualityTask ?? "--")
                StatRow(label: "Rollouts / Episodes", value: rolloutText(gate))
                StatRow(label: "Reward Avg", value: format(gate?.rewardAverage))
                StatRow(label: "Task Pass Rate", value: percent(gate?.taskPassRate))
                StatRow(label: "Hold Time", value: holdTimeText(gate))
                StatRow(label: "Hold Ratio Min", value: format(gate?.minimumHoldTimeRatio))
                StatRow(label: "Altitude Error", value: altitudeErrorText(gate))
                StatRow(label: "Altitude Ratio Max", value: format(gate?.maximumAltitudeErrorRatio))
                StatRow(label: "Worst Case", value: worstCaseText(gate))
                StatRow(label: "Worker Throughput Min", value: format(gate?.minimumWorkerThroughput))
                StatRow(label: "Primary Reject", value: gate?.primaryRejectReason ?? "--")
                if let path = gate?.artifactDirectory.path {
                    Text(path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } label: {
            HStack {
                Label("Post Regression Gate", systemImage: "checkmark.seal.fill")
                Spacer()
                GateBadge(value: gate?.accepted)
            }
        }
    }

    private func rolloutText(_ gate: PostRegressionGateState?) -> String {
        guard let gate else { return "--" }
        return "\(gate.rolloutCount) / \(gate.episodeCount)"
    }

    private func holdTimeText(_ gate: PostRegressionGateState?) -> String {
        guard let gate else { return "--" }
        return "\(format(gate.achievedHoldTime)) / \(format(gate.requiredHoldTime))"
    }

    private func altitudeErrorText(_ gate: PostRegressionGateState?) -> String {
        guard let gate else { return "--" }
        return "\(format(gate.maxAltitudeErrorAfterWarmup)) <= \(format(gate.tolerance))"
    }

    private func worstCaseText(_ gate: PostRegressionGateState?) -> String {
        guard let gate else { return "--" }
        let track = gate.worstTrack ?? "--"
        let scenario = gate.worstScenarioID ?? "--"
        return "\(track) / \(scenario)"
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.3f", value)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f%%", value * 100)
    }
}

struct LearningCampaignView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                TextField("Campaign artifact directory", text: $model.learningCampaignArtifactDirectory)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: KuyuSpacing.xs) {
                    Button(model.isLearningCampaignRunning ? "Running" : "Run") {
                        model.startLearningCampaign()
                    }
                    .disabled(model.isLearningCampaignRunning)
                    Button("Stop") { model.stopLearningCampaign() }
                        .disabled(!model.isLearningCampaignRunning)
                    Button("Use Current") { model.useCurrentLearningCampaignArtifactRoot() }
                    Button("Load") { model.loadLearningCampaignArtifacts() }
                    Button(model.learningCampaignMonitorEnabled ? "Stop" : "Watch") {
                        if model.learningCampaignMonitorEnabled {
                            model.stopLearningCampaignMonitoring()
                        } else {
                            model.startLearningCampaignMonitoring()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: model.learningCampaignProgressFraction, total: 1)
                    HStack(spacing: KuyuSpacing.sm) {
                        StatRow(label: "Phase", value: model.learningCampaignCurrentPhase, compact: true)
                        StatRow(label: "Progress", value: String(format: "%.0f%%", model.learningCampaignProgressFraction * 100), compact: true)
                    }
                    if let event = model.learningCampaignLatestEvent {
                        Text(event)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if let state = model.learningCampaignState {
                    campaignSummary(state)
                    generationTable(state)
                } else if let error = model.learningCampaignError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("No campaign loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            HStack {
                Label("Learning Campaign", systemImage: "flag.checkered")
                Spacer()
                if model.learningCampaignMonitorEnabled {
                    StatusPill("watching", tone: .info)
                }
            }
        }
    }

    private func campaignSummary(_ state: LearningCampaignRunStoreState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            StatRow(label: "Status", value: state.statusLabel)
            StatRow(label: "Task", value: "\(state.task) | \(state.suiteSummary)")
            StatRow(label: "Accepted", value: "\(state.acceptedCount)/\(state.seedCount)")
            StatRow(label: "Validation", value: state.validationLabel)
            if let delta = state.bestDelta {
                StatRow(label: "Best Delta", value: String(format: "%.3f", delta))
            }
            if let retention = state.retention {
                StatRow(
                    label: "Pruned",
                    value: ByteCountFormatter.string(fromByteCount: retention.prunedByteCount, countStyle: .file)
                )
            }
            if let event = state.latestEvent {
                StatRow(label: "Latest", value: event.event)
            }
        }
    }

    private func generationTable(_ state: LearningCampaignRunStoreState) -> some View {
        let rows = Array(state.latestGenerations.prefix(6))
        return VStack(alignment: .leading, spacing: 2) {
            Text("Generations")
                .font(.caption)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text("No generations yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: KuyuSpacing.sm) {
                        Text(row.seed)
                            .frame(width: 64, alignment: .leading)
                        Text("g\(row.generationIndex)")
                            .frame(width: 28, alignment: .leading)
                        Text(row.accepted ? "accepted" : (row.incumbentImproved ? "improved" : "searching"))
                            .frame(width: 72, alignment: .leading)
                            .foregroundStyle(row.accepted ? .green : (row.incumbentImproved ? .blue : .secondary))
                        Text(row.bestFitness.map { String(format: "%.2f", $0) } ?? "--")
                            .frame(width: 54, alignment: .trailing)
                        Text(row.bestVsIncumbentDelta.map { String(format: "%+.2f", $0) } ?? "--")
                            .frame(width: 54, alignment: .trailing)
                        Text(String(format: "mut %.3f", row.mutationRate))
                            .frame(width: 66, alignment: .trailing)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SensorSignalsCard: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            VStack(spacing: KuyuSpacing.xs) {
                if sensorDefinitions.isEmpty {
                    if model.lastSensorSamples.isEmpty {
                        emptyText
                    } else {
                        ForEach(sortedSamples, id: \.channelIndex) { sample in
                            SignalBar(
                                label: "S\(sample.channelIndex)",
                                value: sample.value,
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
                                maxValue: maxRangeValue(for: definition)
                            )
                        } else {
                            MissingSignalRow(label: "\(definition.name) [\(definition.units)]")
                        }
                    }
                }
            }
        } label: {
            Label("Sensor Signals", systemImage: "antenna.radiowaves.left.and.right")
        }
    }

    private var emptyText: some View {
        Text("No sensor samples")
            .font(.callout)
            .foregroundStyle(.secondary)
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

struct ActuatorSignalsCard: View {
    @Bindable var model: SimulationViewModel
    @State private var viewMode: ActuatorViewMode = .motorNerve

    private enum ActuatorViewMode: CaseIterable {
        case motorNerve
        case motor

        var label: String {
            switch self {
            case .motorNerve: return "MotorNerve"
            case .motor: return "Actuator"
            }
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                Picker("Actuator View", selection: $viewMode) {
                    ForEach(ActuatorViewMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: viewMode) { _, mode in
                    model.emitUIAction(level: .info, message: "Actuator view mode changed", action: "setActuatorViewMode", metadata: [
                        "mode": mode.label
                    ])
                }

                Group {
                    switch viewMode {
                    case .motorNerve:
                        if motorNerveOutputs.isEmpty {
                            Text("No MotorNerve output")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: KuyuSpacing.xs) {
                                ForEach(Array(motorNerveOutputs.enumerated()), id: \.offset) { index, output in
                                    let definition = index < actuatorDefinitions.count ? actuatorDefinitions[index] : nil
                                    let label = definition.map { "\($0.name) [\($0.units)]" } ?? "u\(index)"
                                    let maxValue = definition.map { maxRangeValue(for: $0) } ?? motorNerveMaxValue
                                    SignalBar(label: label, value: output, maxValue: maxValue)
                                }
                            }
                        }
                    case .motor:
                        actuatorContent
                    }
                }
            }
        } label: {
            Label("Actuators", systemImage: "gearshape.2")
        }
    }

    @ViewBuilder
    private var actuatorContent: some View {
        if !actuatorChannels.isEmpty {
            VStack(spacing: KuyuSpacing.xs) {
                ForEach(actuatorChannels, id: \.id) { channel in
                    let definition = actuatorDefinitions.first { $0.id == channel.id }
                    let label = definition.map { "\($0.name) [\($0.units)]" } ?? channel.id
                    let maxValue = definition.map { maxRangeValue(for: $0) } ?? actuatorMaxValue
                    SignalBar(label: label, value: channel.value, maxValue: maxValue)
                }
            }
        } else if !sortedActuatorValues.isEmpty {
            VStack(spacing: KuyuSpacing.xs) {
                ForEach(sortedActuatorValues, id: \.index.rawValue) { command in
                    let index = Int(command.index.rawValue)
                    let definition = index < actuatorDefinitions.count ? actuatorDefinitions[index] : nil
                    let label = definition.map { "\($0.name) [\($0.units)]" } ?? "A\(command.index.rawValue)"
                    let maxValue = definition.map { maxRangeValue(for: $0) } ?? actuatorMaxValue
                    SignalBar(label: label, value: command.value, maxValue: maxValue)
                }
            }
        } else {
            Text("No actuator output")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
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
}

struct ManasSignalsCard: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                driveIntents
                Divider().opacity(0.4)
                reflexCorrections
            }
        } label: {
            Label("Manas Signals", systemImage: "brain")
        }
    }

    @ViewBuilder
    private var driveIntents: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            Text("Drive Intents")
                .font(.caption)
                .foregroundStyle(.secondary)
            if sortedDriveIntents.isEmpty {
                Text("No drive intents")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedDriveIntents, id: \.index.rawValue) { intent in
                    let definition = driveDefinitions[safe: Int(intent.index.rawValue)]
                    let label = definition.map { "\($0.name) [\($0.units)]" } ?? "Drive \(intent.index.rawValue)"
                    let maxValue = definition.map { maxRangeValue(for: $0) } ?? driveMaxValue
                    SignalBar(label: label, value: intent.activation, maxValue: maxValue)
                }
            }
        }
    }

    @ViewBuilder
    private var reflexCorrections: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            Text("Reflex Corrections")
                .font(.caption)
                .foregroundStyle(.secondary)
            if sortedReflexCorrections.isEmpty {
                Text("No reflex corrections")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedReflexCorrections, id: \.driveIndex.rawValue) { correction in
                    let definition = reflexDefinitions[safe: Int(correction.driveIndex.rawValue)]
                    let label = definition.map { $0.name } ?? "D\(correction.driveIndex.rawValue)"
                    HStack(spacing: KuyuSpacing.sm) {
                        Text(label)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 32, alignment: .leading)
                        Text(String(format: "Δ %.3f", correction.delta))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                        Text(String(format: "C %.2f", correction.clampMultiplier))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(String(format: "D %.2f", correction.damping))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    private var sortedDriveIntents: [DriveIntent] {
        model.lastDriveIntents.sorted { $0.index.rawValue < $1.index.rawValue }
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

struct MotorNerveChainCard: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            if stages.isEmpty {
                Text("No MotorNerve stages")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(stage.id) [\(stage.type.rawValue)]")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("in: \(stage.inputs.map(signalLabel).joined(separator: ", "))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("out: \(stage.outputs.map(signalLabel).joined(separator: ", "))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if index != stages.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        } label: {
            Label("MotorNerve Chain", systemImage: "link")
        }
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

struct ManualActuatorControlCard: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                Text("Forces baseline controller during single runs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Link all actuators", isOn: $model.manualActuatorLinked)
                    .font(.callout)
                    .toggleStyle(.switch)

                Group {
                    if model.manualActuatorLinked {
                        linkedSliderSection
                    } else {
                        individualSliderSection
                    }
                }
                .disabled(!model.manualActuatorEnabled)
            }
        } label: {
            HStack {
                Label("Manual Actuator Override", systemImage: "hand.raised")
                Spacer()
                Toggle("", isOn: $model.manualActuatorEnabled)
                    .labelsHidden()
                    .controlSize(.small)
            }
        }
    }

    private var linkedSliderSection: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack {
                Text("Linked ratio")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", model.manualActuatorMaster * 100.0))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            Slider(value: $model.manualActuatorMaster, in: 0.0...1.0)
            if !linkedPreviewText.isEmpty {
                Text(linkedPreviewText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var individualSliderSection: some View {
        VStack(spacing: KuyuSpacing.sm) {
            ForEach(Array(actuatorLabels.enumerated()), id: \.offset) { index, label in
                VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                    HStack {
                        Text(labelWithUnit(for: index, label: label))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(formattedValue(for: index))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    Slider(value: binding(for: index), in: range(for: index))
                    HStack {
                        Text(formattedRangeBound(range(for: index).lowerBound, unit: unit(for: index)))
                        Spacer()
                        Text(formattedRangeBound(range(for: index).upperBound, unit: unit(for: index)))
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }
        }
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
            get: { model.manualActuatorValuePhysical(index: index) },
            set: { value in model.setManualActuatorValuePhysical(index: index, value: value) }
        )
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
        if unit.isEmpty { return label }
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

struct HoverTestCard: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        let isLocked = model.isLoopRunning || model.isTraining
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                Text("Adjust hover thrust scale to verify vertical motion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: KuyuSpacing.xs) {
                    Button("0.9 ↓") { model.setHoverThrustScale(0.9, source: "ui.hoverTestDown") }
                    Button("1.0 •") { model.setHoverThrustScale(1.0, source: "ui.hoverTestNeutral") }
                    Button("1.1 ↑") { model.setHoverThrustScale(1.1, source: "ui.hoverTestUp") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1.0)
                if isLocked {
                    Text("Disabled while training loop is running.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Current: \(String(format: "%.2f", model.hoverThrustScale))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("Hover Test", systemImage: "airplane")
        }
    }
}

struct ManasSignalFlowCard: View {
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                Text("Runtime control path (left → right)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: KuyuSpacing.xs) {
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
                    .padding(.vertical, 2)
                }
            }
        } label: {
            Label("Manas Signal Flow", systemImage: "arrow.triangle.branch")
        }
    }
}

struct ControlBoundaryCard: View {
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                HStack(spacing: KuyuSpacing.xs) {
                    Text("MotorNerve: Descriptor-defined mapping")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("Manas: Learnable Core + Reflex")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("MotorNerve is a protocol mapping, not a safety filter. Reflex applies bounded corrections and MotorNerve remains deterministic for a given descriptor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("Control Boundary", systemImage: "rectangle.split.2x1")
        }
    }
}

// MARK: - Small reusable bits

private struct FlowNode: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, KuyuSpacing.sm)
            .padding(.vertical, KuyuSpacing.xs)
            .overlay(
                RoundedRectangle(cornerRadius: KuyuRadius.small)
                    .stroke(.secondary.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: KuyuRadius.small))
    }
}

private struct FlowArrow: View {
    var body: some View {
        Text("→")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }
}

private struct QualityGauge: View {
    let label: String
    let value: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percentText)
                    .font(.system(.callout, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            ProgressView(value: clampedValue, total: 1.0)
                .tint(tint)
        }
    }

    private var clampedValue: Double {
        guard let value else { return 0 }
        return min(max(value, 0), 1)
    }

    private var percentText: String {
        guard let value else { return "--" }
        return String(format: "%.0f%%", min(max(value, 0), 1) * 100)
    }
}

private struct PhaseBadge: View {
    let phase: TrainingLiveStatus.Phase

    var body: some View {
        Text(phase.rawValue)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch phase {
        case .completed: return .green
        case .failed, .stopped: return .orange
        case .paused: return .yellow
        case .idle: return .secondary
        default: return .blue
        }
    }
}

private struct PhaseDot: View {
    let phase: TrainingLiveStatus.Phase

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch phase {
        case .completed: return .green
        case .failed, .stopped: return .orange
        case .paused: return .yellow
        case .idle: return .secondary
        default: return .blue
        }
    }
}

private struct GateBadge: View {
    let value: Bool?

    var body: some View {
        Text(label)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private var label: String {
        guard let value else { return "pending" }
        return value ? "accepted" : "rejected"
    }

    private var color: Color {
        guard let value else { return .secondary }
        return value ? .green : .orange
    }
}

private struct FlagBadge: View {
    let label: String
    let active: Bool?

    var body: some View {
        Text("\(label): \(active == true ? "on" : "off")")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        active == true ? .orange : .secondary
    }
}

private struct SignalBar: View {
    let label: String
    let value: Double
    let maxValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.3f", value))
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            ProgressView(value: clamp(value), total: maxValue)
                .tint(.accentColor)
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
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text("missing")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.orange)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

#Preview {
    let buffer = UILoggingBootstrap.buffer
    let logStore = UILogStore(buffer: buffer)
    let model = SimulationViewModel(logStore: logStore)
    return TrainingDashboardView(
        model: model,
        roll: 0.1,
        pitch: -0.2,
        yaw: 0.3,
        position: Axis3(x: 0, y: 0, z: 0),
        renderInfo: nil
    )
    .frame(width: 1280, height: 800)
}
