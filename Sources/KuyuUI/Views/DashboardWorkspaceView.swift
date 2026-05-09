import SwiftUI

struct DashboardWorkspaceView: View {
    @Bindable var model: SimulationViewModel
    @State private var showBottomSection: Bool = true
    @State private var selectedDetailTab: RunsAndLogsDetailTab = .details

    var body: some View {
        CollapsibleSplitView(isExpanded: $showBottomSection) {
            ScrollView {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    HStack(alignment: .top, spacing: KuyuSpacing.md) {
                        KeyTrainingChartsView(model: model)
                            .frame(maxWidth: .infinity)

                        RunQueueView(model: model)
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
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

            ScrollView {
                Group {
                    switch selectedDetailTab {
                    case .details:
                        RunsAndLogsDetailView(model: model)
                    case .logs:
                        LogSummaryView(model: model)
                    case .diagnostics:
                        CampaignDiagnosticsView(model: model)
                    case .artifacts:
                        TrainingArtifactsView(model: model)
                    }
                }
                .padding(KuyuSpacing.sm)
            }
        }
    }
}

private enum RunsAndLogsDetailTab: String, CaseIterable {
    case details
    case logs
    case diagnostics
    case artifacts

    var label: String {
        switch self {
        case .details:
            return "Details"
        case .logs:
            return "Logs"
        case .diagnostics:
            return "Diagnostics"
        case .artifacts:
            return "Artifacts"
        }
    }

    var systemImage: String {
        switch self {
        case .details:
            return "info.circle"
        case .logs:
            return "doc.text"
        case .diagnostics:
            return "exclamationmark.triangle"
        case .artifacts:
            return "shippingbox"
        }
    }
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
                    StatRow(label: "Generations", value: generationsText, compact: true)
                    StatRow(label: "Candidates", value: candidatesText, compact: true)
                    StatRow(label: "Parallelism", value: model.learningCampaignState?.actualParallelismLabel ?? "--", compact: true)
                    StatRow(label: "Best Delta", value: bestDeltaText, compact: true)
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
        return "\(state.generations.count)"
    }

    private var candidatesText: String {
        guard let state = model.learningCampaignState else { return "--" }
        return "\(state.candidateEvaluationCount)"
    }

    private var bestDeltaText: String {
        guard let value = model.learningCampaignState?.bestDelta else { return "--" }
        return String(format: "%+.3f", value)
    }

    private var finalCheckpointText: String {
        guard let path = model.learningCampaignState?.finalCheckpoint else { return "--" }
        return URL(fileURLWithPath: path).lastPathComponent
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
