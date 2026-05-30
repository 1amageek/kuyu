import SwiftUI

#if os(macOS)
import AppKit
#endif

struct DashboardWorkspaceView: View {
    @Bindable var model: SimulationViewModel
    @State private var showBottomSection: Bool = true
    @State private var selectedDetailTab: RunsAndLogsDetailTab = .activity

    var body: some View {
        let pose = RobotPoseSnapshot.current(model: model)
        CollapsibleSplitView(isExpanded: $showBottomSection) {
            ScrollView {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    if showsFirstRunCTA {
                        firstRunCTA
                    }

                    KeyTrainingChartsView(model: model)
                        .frame(maxWidth: .infinity)

                    PopulationSimulationView(model: model)
                        .frame(maxWidth: .infinity)

                    VectorizedExecutionView(model: model)
                        .frame(maxWidth: .infinity)

                    HStack(alignment: .top, spacing: KuyuSpacing.md) {
                        PolicyLineageGraphView(state: model.learningCampaignState)
                        KuyuSimulationPreviewView(
                            model: model,
                            roll: pose.roll,
                            pitch: pose.pitch,
                            yaw: pose.yaw,
                            position: pose.position,
                            renderInfo: pose.renderInfo
                        )
                    }

                    HStack(alignment: .top, spacing: KuyuSpacing.md) {
                        RunQueueView(model: model)
                        LearningCampaignActivityView(model: model)
                    }
                }
                .padding(KuyuSpacing.md)
            }
        } content: {
            HStack(spacing: 0) {
                ScrollView {
                    RunListView(model: model)
                        .padding(KuyuSpacing.sm)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                runsAndLogsDetail
                .frame(minWidth: 320, idealWidth: 480, maxWidth: 600, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        } header: {
            Label("Runs & Logs", systemImage: "list.bullet.rectangle")
                .font(.callout.weight(.semibold))
        }
    }

    private var showsFirstRunCTA: Bool {
        model.runs.isEmpty
            && !model.isLearningCampaignRunning
            && !model.isRunning
            && model.learningCampaignState == nil
    }

    private var firstRunCTA: some View {
        GroupBox {
            HStack(spacing: KuyuSpacing.md) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run your first training")
                        .font(.headline)
                    Text("Launch a learning campaign now, or design a strategy in the Training workspace first.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.startLearningCampaign()
                } label: {
                    Label("Start Learning Campaign", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(KuyuSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var runsAndLogsDetail: some View {
        VStack(spacing: 0) {
            Picker("Runs and logs detail", selection: $selectedDetailTab) {
                ForEach(RunsAndLogsDetailTab.allCases, id: \.self) { tab in
                    Label(tab.label, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(KuyuSpacing.sm)

            Divider()

            Group {
                if selectedDetailTab == .rawLogs {
                    RawLearningCampaignLogView(model: model)
                } else {
                    ScrollView {
                        Group {
                            switch selectedDetailTab {
                            case .activity:
                                LearningCampaignRunLogView(model: model)
                            case .summary:
                                RunsAndLogsDetailView(model: model)
                            case .diagnostics:
                                CampaignDiagnosticsView(model: model)
                            case .rawLogs:
                                EmptyView()
                            case .artifacts:
                                TrainingArtifactsView(model: model)
                            }
                        }
                        .padding(KuyuSpacing.sm)
                    }
                }
            }
        }
    }
}

private enum RunsAndLogsDetailTab: String, CaseIterable {
    case activity
    case summary
    case diagnostics
    case rawLogs
    case artifacts

    var label: String {
        switch self {
        case .activity:
            return "Activity"
        case .summary:
            return "Summary"
        case .diagnostics:
            return "Diagnostics"
        case .rawLogs:
            return "Raw Logs"
        case .artifacts:
            return "Artifacts"
        }
    }

    var systemImage: String {
        switch self {
        case .activity:
            return "list.bullet.rectangle.portrait"
        case .summary:
            return "info.circle"
        case .diagnostics:
            return "exclamationmark.triangle"
        case .rawLogs:
            return "doc.text"
        case .artifacts:
            return "shippingbox"
        }
    }
}

private struct LearningCampaignRunLogView: View {
    @Bindable var model: SimulationViewModel
    @State private var filter: RunLogFilter = .activity

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            HStack {
                Label("Activity", systemImage: "list.bullet.rectangle.portrait")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("Copy") {
                    copyToPasteboard(transcript)
                }
                .buttonStyle(.bordered)
                .disabled(transcript.isEmpty)
            }

            Picker("Run log filter", selection: $filter) {
                ForEach(RunLogFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if entries.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "list.bullet.rectangle.portrait",
                    description: Text("Start a learning campaign or load artifacts to inspect preflight, generation, candidate, regression, checkpoint, and artifact activity.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                    ForEach(entries) { entry in
                        LearningCampaignEventRow(entry: entry)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var entries: [LearningCampaignRunLogRecord] {
        filter.apply(to: model.learningCampaignRunLog)
    }

    private var transcript: String {
        LearningCampaignRunLogFormatter.transcript(entries: entries)
    }

    private func copyToPasteboard(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

private enum RunLogFilter: String, CaseIterable {
    case activity
    case progress
    case generation
    case candidate
    case regression
    case checkpoint
    case warnings
    case errors
    case all

    var label: String {
        switch self {
        case .activity: return "Activity"
        case .progress: return "Progress"
        case .generation: return "Generation"
        case .candidate: return "Candidate"
        case .regression: return "Regression"
        case .checkpoint: return "Checkpoint"
        case .warnings: return "Warnings"
        case .errors: return "Errors"
        case .all: return "All"
        }
    }

    func apply(to entries: [LearningCampaignRunLogRecord]) -> [LearningCampaignRunLogRecord] {
        entries.filter { entry in
            switch self {
            case .activity:
                return entry.category != .artifact
            case .progress:
                return entry.category == .lifecycle || entry.category == .preflight || entry.category == .seed
            case .generation:
                return entry.category == .generation
            case .candidate:
                return entry.category == .candidate
            case .regression:
                return entry.category == .regression
            case .checkpoint:
                return entry.category == .checkpointEvaluation || entry.category == .regression
            case .warnings:
                return entry.level == .warning
            case .errors:
                return entry.level == .failure
            case .all:
                return true
            }
        }
    }
}

private struct LearningCampaignEventRow: View {
    let entry: LearningCampaignRunLogRecord

    var body: some View {
        HStack(alignment: .top, spacing: KuyuSpacing.sm) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: KuyuSpacing.xs) {
                    Text(timeText)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(entry.phase)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                    Spacer(minLength: 0)
                    Text(entry.category.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.title)
                    .font(.caption.weight(.semibold))
                    .textSelection(.enabled)

                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !entry.metadata.isEmpty {
                    Text(entry.metadata.joined(separator: "  "))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(KuyuSpacing.xs)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: KuyuRadius.small))
    }

    private var iconName: String {
        switch entry.category {
        case .lifecycle:
            return "flag.checkered"
        case .preflight:
            return "checklist"
        case .checkpointEvaluation:
            return "target"
        case .regression:
            return "checkmark.seal"
        case .seed:
            return "leaf"
        case .generation:
            return "chart.line.uptrend.xyaxis"
        case .candidate:
            return "square.stack.3d.up"
        case .artifact:
            return "shippingbox"
        case .diagnostics:
            return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch entry.level {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .failure:
            return .red
        }
    }

    private var timeText: String {
        Self.timeFormatter.string(from: entry.timestamp)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct RunsAndLogsDetailView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                    StatRow(label: "Status", value: model.learningCampaignState?.statusLabel ?? "--", compact: true)
                    StatRow(label: "Validation", value: model.learningCampaignState?.validationLabel ?? "--", compact: true)
                    StatRow(label: "Accepted", value: acceptedText, compact: true)
                    StatRow(label: "Task", value: taskText, compact: true)
                    if let state = model.learningCampaignState, state.hasTrainingStageIdentity {
                        StatRow(label: "Stage", value: state.trainingStageLabel, compact: true)
                        StatRow(label: "Stage Kind", value: state.trainingStageKindLabel, compact: true)
                    }
                    StatRow(label: "Phase", value: model.learningCampaignCurrentPhase, compact: true)
                    StatRow(label: "Latest Event", value: model.learningCampaignLatestEvent ?? "--", compact: true)
                    if let primaryIssue {
                        StatRow(label: "Primary Issue", value: primaryIssue, valueColor: .orange, compact: true)
                    }
                }
            } label: {
                Label("Selected Run", systemImage: "target")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                    StatRow(label: "Generation Budget", value: generationsText, compact: true)
                    StatRow(label: "Candidates", value: candidatesText, compact: true)
                    StatRow(label: "Parallelism", value: model.learningCampaignState?.actualParallelismLabel ?? "--", compact: true)
                    StatRow(label: "Best Fitness", value: bestFitnessText, compact: true)
                    StatRow(label: "Best Delta", value: bestDeltaText, compact: true)
                    StatRow(label: "Task Pass", value: taskPassText, compact: true)
                    StatRow(label: "Hold / Altitude", value: qualityText, compact: true)
                    StatRow(label: "Final Checkpoint", value: finalCheckpointText, compact: true)
                }
            } label: {
                Label("Learning Summary", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var acceptedText: String {
        guard let state = model.learningCampaignState else { return "--" }
        return "\(state.acceptedCount)/\(state.seedCount)"
    }

    private var taskText: String {
        guard let state = model.learningCampaignState else { return model.taskMode.rawValue }
        return "\(state.task) | \(state.suiteSummary)"
    }

    private var primaryIssue: String? {
        if let reason = model.learningCampaignState?.primaryFailureReason {
            return reason
        }
        if let reason = model.lastPostRegressionGate?.primaryRejectReason {
            return reason
        }
        return model.learningCampaignError
    }

    private var generationsText: String {
        guard let state = model.learningCampaignState else { return "--" }
        return "\(state.completedGenerationCount) / \(state.plannedGenerationCount)"
    }

    private var candidatesText: String {
        guard let state = model.learningCampaignState else { return "--" }
        return "\(state.liveCandidateEvaluationCount) / \(state.plannedCandidateEvaluationCount)"
    }

    private var bestFitnessText: String {
        guard let value = model.learningCampaignState?.bestFitness else { return "--" }
        return String(format: "%.3f", value)
    }

    private var bestDeltaText: String {
        guard let state = model.learningCampaignState,
              let value = state.bestFitnessDeltaFromInitial ?? state.bestDelta else { return "--" }
        return String(format: "%+.3f", value)
    }

    private var taskPassText: String {
        guard let value = model.learningCampaignState?.bestTaskPassRate else { return "--" }
        return String(format: "%.0f%%", value * 100)
    }

    private var qualityText: String {
        guard let state = model.learningCampaignState else { return "--" }
        let hold = state.bestHoldTimeRatio.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
        let altitude = state.bestAltitudeErrorRatio.map { String(format: "%.2f", $0) } ?? "--"
        return "\(hold) / \(altitude)"
    }

    private var finalCheckpointText: String {
        guard let path = model.learningCampaignState?.finalCheckpoint else { return "--" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

private struct RawLearningCampaignLogView: View {
    @Bindable var model: SimulationViewModel
    @State private var rawLogFilterText = ""

    var body: some View {
        VStack(spacing: 0) {
            MonospacedLogOutputView(
                lines: rawLogLines,
                emptyMessage: "No raw logs yet",
                filterText: rawLogFilterText
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            rawLogFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rawLogFooter: some View {
        HStack(spacing: KuyuSpacing.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)

            TextField("Filter raw logs", text: $rawLogFilterText)
                .textFieldStyle(.plain)

            if !rawLogFilterText.isEmpty {
                Button {
                    rawLogFilterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear Filter")
            }

            Spacer()

            Button {
                copyRawLogsToPasteboard(filteredRawLogText)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .disabled(filteredRawLogText.isEmpty)
            .help("Copy Visible Raw Logs")
        }
        .font(.callout)
        .padding(.horizontal, KuyuSpacing.sm)
        .frame(height: 34)
        .background(.bar)
    }

    private var rawLogLines: [MonospacedLogLine] {
        var lines: [MonospacedLogLine] = []
        let structuredLines = LearningCampaignRunLogFormatter
            .transcript(entries: model.learningCampaignRunLog)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in
                MonospacedLogLine(id: "run-\(index)", text: String(line))
            }
        lines.append(contentsOf: structuredLines)

        if !lines.isEmpty && !model.logStore.entries.isEmpty {
            lines.append(MonospacedLogLine(id: "separator-ui-logs", text: "--- UI Runtime Logs ---"))
        }

        lines.append(contentsOf: model.logStore.entries.map { entry in
            MonospacedLogLine(id: "ui-\(entry.id.uuidString)", text: uiLogLine(for: entry))
        })
        return lines
    }

    private var filteredRawLogText: String {
        let filter = rawLogFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = filter.isEmpty
            ? rawLogLines
            : rawLogLines.filter { $0.text.localizedStandardContains(filter) }
        return visible.map(\.text).joined(separator: "\n")
    }

    private func uiLogLine(for entry: UILogEntry) -> String {
        let time = LogEntryRowView.formatter.string(from: entry.timestamp)
        let level = entry.level.rawValue.uppercased()
        let metadata = entry.metadata.isEmpty
            ? ""
            : " " + entry.metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        return "\(time) \(level) \(entry.label) \(entry.message)\(metadata)"
    }

    private func copyRawLogsToPasteboard(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

private struct CampaignDiagnosticsView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                    StatRow(label: "Primary Issue", value: primaryIssue ?? "--", valueColor: primaryIssue == nil ? nil : .orange)
                    StatRow(label: "Status", value: model.learningCampaignState?.statusLabel ?? "--", compact: true)
                    StatRow(label: "Validation", value: model.learningCampaignState?.validationLabel ?? "--", compact: true)
                    StatRow(label: "Latest Event", value: model.learningCampaignLatestEvent ?? "--", compact: true)
                }
            } label: {
                Label("Failure Reason", systemImage: "exclamationmark.triangle")
            }

            CopyableTextBlockView(
                title: "Diagnostics",
                text: diagnosticsText,
                emptyText: "No diagnostics recorded"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryIssue: String? {
        if let reason = model.learningCampaignState?.primaryFailureReason {
            return reason
        }
        if let reason = model.lastPostRegressionGate?.primaryRejectReason {
            return reason
        }
        return model.learningCampaignError
    }

    private var diagnosticsText: String {
        var lines: [String] = []
        let diagnosticRecords = model.learningCampaignRunLog.filter { record in
            record.category == .diagnostics || record.level == .warning || record.level == .failure
        }
        if !diagnosticRecords.isEmpty {
            lines.append("structuredRunLogDiagnostics:")
            lines.append(LearningCampaignRunLogFormatter.transcript(entries: diagnosticRecords))
        }
        if let error = model.learningCampaignError {
            lines.append("uiError=\(error)")
        }
        if let state = model.learningCampaignState {
            lines.append(state.diagnosticText)
        }
        if let gate = model.lastPostRegressionGate, !gate.rejectReasons.isEmpty {
            lines.append("postRegressionRejectReasons:")
            lines.append(contentsOf: gate.rejectReasons.map { "- \($0)" })
        }
        if let event = model.learningCampaignLatestEvent {
            lines.append("latestNote=\(event)")
        }
        return lines.joined(separator: "\n")
    }
}
