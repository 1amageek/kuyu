import KuyuTraining
import SwiftUI

/// Workspace that attaches to training runs under the run root: a live run
/// list, per-run detail read from the run contract, and pause/resume/stop
/// control through the contract's file-based channel.
struct TrainingRunsWorkspaceView: View {
    @Bindable var model: TrainingRunsViewModel

    var body: some View {
        HSplitView {
            runList
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
            detailPane
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await model.monitor()
        }
    }

    // MARK: - Run list

    private var runList: some View {
        VStack(spacing: 0) {
            if let error = model.lastError {
                errorBanner(error)
            }
            List(selection: $model.selectedRunID) {
                Section {
                    ForEach(model.items) { item in
                        TrainingRunRowView(item: item)
                            .tag(item.id)
                    }
                } header: {
                    Text(model.runRootPath ?? "run root unresolved")
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .overlay {
                if model.items.isEmpty && model.lastError == nil {
                    ContentUnavailableView(
                        "No Training Runs",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Start one with `kuyu train`. Runs appear here as soon as their manifest is written.")
                    )
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(KuyuSpacing.sm)
        .background(.yellow.opacity(0.12))
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let detail = model.detail {
            ScrollView {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    detailHeader(detail)
                    identitySection(detail)
                    outcomeSection(detail)
                    journalSection(detail)
                    controlSection(detail)
                }
                .padding(KuyuSpacing.md)
            }
        } else {
            ContentUnavailableView(
                "No Run Selected",
                systemImage: "sidebar.left",
                description: Text("Select a run to inspect its manifest, journal, and control state.")
            )
        }
    }

    private func detailHeader(_ detail: TrainingRunDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
                Text(detail.runID)
                    .font(.system(.headline, design: .monospaced))
                    .textSelection(.enabled)
                StatusPill(detail.liveness.displayLabel, tone: detail.liveness.pillTone)
                Spacer(minLength: 0)
            }
            HStack(spacing: KuyuSpacing.sm) {
                Button("Pause") { submit(.pause) }
                    .disabled(!canPause(detail.liveness))
                Button("Resume") { submit(.resume) }
                    .disabled(!canResume(detail.liveness))
                Button("Stop", role: .destructive) { submit(.stop) }
                    .disabled(!canStop(detail.liveness))
                if model.pendingControlSequence != nil {
                    ProgressView()
                        .controlSize(.small)
                    Text("awaiting acknowledgment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
        }
    }

    private func identitySection(_ detail: TrainingRunDetailSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Task", value: detail.manifest.task, compact: true)
                StatRow(label: "Profile", value: detail.manifest.profile, compact: true)
                StatRow(label: "Version", value: detail.manifest.semanticVersion, compact: true)
                StatRow(
                    label: "Code",
                    value: "\(String(detail.manifest.code.gitHead.prefix(12)))\(detail.manifest.code.gitDirty ? " (dirty)" : "")",
                    compact: true
                )
                StatRow(
                    label: "Determinism",
                    value: "tier=\(detail.manifest.determinism.tier) seed=\(detail.manifest.determinism.mlxGlobalSeed)",
                    compact: true
                )
                StatRow(
                    label: "Created",
                    value: detail.manifest.createdAt.formatted(date: .abbreviated, time: .standard),
                    compact: true
                )
                StatRow(
                    label: "Host",
                    value: "\(detail.manifest.host.hostName) pid=\(detail.manifest.host.processIdentifier)",
                    compact: true
                )
            }
        } label: {
            Label("Identity", systemImage: "doc.badge.gearshape")
        }
    }

    private func outcomeSection(_ detail: TrainingRunDetailSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Status", value: detail.outcome.status.rawValue, compact: true)
                StatRow(
                    label: "Updated",
                    value: detail.outcome.updatedAt.formatted(date: .abbreviated, time: .standard),
                    compact: true
                )
                if let finalIteration = detail.outcome.finalIteration {
                    StatRow(label: "Final Iteration", value: "\(finalIteration)", compact: true)
                }
                if let failureReason = detail.outcome.failureReason {
                    StatRow(label: "Failure", value: failureReason, valueColor: .red, compact: true)
                }
                if let acceptedCheckpointPath = detail.outcome.acceptedCheckpointPath {
                    StatRow(label: "Accepted Checkpoint", value: acceptedCheckpointPath, compact: true)
                }
                if let heartbeat = detail.heartbeat {
                    StatRow(
                        label: "Heartbeat",
                        value: "iter=\(heartbeat.iteration) \(heartbeat.phase) at \(heartbeat.updatedAt.formatted(date: .omitted, time: .standard))",
                        compact: true
                    )
                } else {
                    StatRow(label: "Heartbeat", value: "none", compact: true)
                }
            }
        } label: {
            Label("Outcome", systemImage: "flag.checkered")
        }
    }

    private func journalSection(_ detail: TrainingRunDetailSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Records", value: "\(detail.journalRecordCount)", compact: true)
                if detail.journalTruncatedTailBytes > 0 {
                    StatRow(
                        label: "Torn Tail",
                        value: "\(detail.journalTruncatedTailBytes) bytes",
                        valueColor: .yellow,
                        compact: true
                    )
                }
                if let lastRecord = detail.lastRecord {
                    StatRow(label: "Last Iteration", value: "\(lastRecord.iteration)", compact: true)
                    ForEach(
                        (lastRecord.evaluation?.metrics ?? [:]).sorted { $0.key < $1.key },
                        id: \.key
                    ) { metric in
                        StatRow(
                            label: metric.key,
                            value: String(format: "%.4f", metric.value),
                            compact: true
                        )
                    }
                    if let checkpoint = lastRecord.checkpoint {
                        StatRow(
                            label: "Checkpoint",
                            value: checkpoint.path,
                            compact: true
                        )
                    }
                }
            }
        } label: {
            Label("Journal", systemImage: "list.bullet.rectangle.portrait")
        }
    }

    private func controlSection(_ detail: TrainingRunDetailSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                if let control = detail.control {
                    StatRow(label: "Sequence", value: "\(control.sequence)", compact: true)
                    if let acknowledgment = control.acknowledgment {
                        StatRow(label: "Command", value: acknowledgment.command, compact: true)
                        StatRow(
                            label: "Result",
                            value: acknowledgment.rejected
                                ? "rejected at iteration \(acknowledgment.iteration)"
                                : "applied at iteration \(acknowledgment.iteration)",
                            valueColor: acknowledgment.rejected ? .red : .green,
                            compact: true
                        )
                        if let reason = acknowledgment.reason {
                            StatRow(label: "Reason", value: reason, compact: true)
                        }
                    } else {
                        StatRow(label: "State", value: "pending (not yet acknowledged)", compact: true)
                    }
                } else {
                    StatRow(label: "State", value: "no commands submitted", compact: true)
                }
            }
        } label: {
            Label("Control", systemImage: "playpause")
        }
    }

    // MARK: - Control gating

    private func submit(_ action: TrainingRunControlAction) {
        Task { await model.submitControl(action) }
    }

    private func canPause(_ liveness: TrainingRunLiveness) -> Bool {
        if case .live = liveness { return true }
        return false
    }

    private func canResume(_ liveness: TrainingRunLiveness) -> Bool {
        if case .paused(processAlive: true) = liveness { return true }
        return false
    }

    private func canStop(_ liveness: TrainingRunLiveness) -> Bool {
        switch liveness {
        case .live, .paused(processAlive: true):
            return true
        case .finished, .interrupted, .paused:
            return false
        }
    }
}

/// One run row: ID, liveness pill, created date, and task label.
private struct TrainingRunRowView: View {
    let item: TrainingRunListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
                Text(item.id)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if let liveness = item.liveness {
                    StatusPill(liveness.displayLabel, tone: liveness.pillTone)
                } else {
                    StatusPill("unreadable", tone: .danger)
                }
            }
            if let unreadableReason = item.unreadableReason {
                Text(unreadableReason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                HStack(spacing: KuyuSpacing.sm) {
                    if let createdAt = item.createdAt {
                        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let task = item.task {
                        Text(task)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private extension TrainingRunLiveness {
    var displayLabel: String {
        switch self {
        case .live(let processIdentifier):
            return "live (pid \(processIdentifier))"
        case .finished(let status):
            return status.rawValue
        case .paused(let processAlive):
            return processAlive ? "paused" : "paused (writer dead)"
        case .interrupted:
            return "interrupted"
        }
    }

    var pillTone: StatusPill.Tone {
        switch self {
        case .live:
            return .info
        case .finished(let status):
            switch status {
            case .completed:
                return .success
            case .cancelled:
                return .neutral
            case .failed:
                return .danger
            case .running, .paused:
                return .warning
            }
        case .paused(let processAlive):
            return processAlive ? .warning : .danger
        case .interrupted:
            return .danger
        }
    }
}

#Preview {
    TrainingRunsWorkspaceView(model: TrainingRunsViewModel())
        .frame(width: 900, height: 600)
}
