import SwiftUI

#if os(macOS)
import AppKit
#endif

struct TrainingMonitorCommandCenterView: View {
    @Bindable var model: SimulationViewModel

    private let signalColumns = [
        GridItem(.adaptive(minimum: 158), spacing: KuyuSpacing.sm, alignment: .topLeading)
    ]

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let snapshot = TrainingMonitorSnapshot(model: model, now: context.date)
            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    monitorHeader(snapshot)
                    ProgressView(value: snapshot.progressFraction, total: 1)
                    signalGrid(snapshot)
                    if !snapshot.alerts.isEmpty {
                        alertStack(snapshot.alerts)
                    }
                    controlStrip(snapshot)
                }
                .padding(KuyuSpacing.xs)
            } label: {
                HStack {
                    Label("Training Monitor", systemImage: "waveform.path.ecg.rectangle")
                    Spacer()
                    StatusPill(snapshot.health.label, tone: tone(snapshot.health))
                }
            }
        }
    }

    private func monitorHeader(_ snapshot: TrainingMonitorSnapshot) -> some View {
        HStack(alignment: .top, spacing: KuyuSpacing.md) {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                Text(snapshot.statusLabel)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(snapshot.latestEvent ?? snapshot.phase)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: KuyuSpacing.xs) {
                Text(String(format: "%.1f%%", snapshot.progressFraction * 100))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                Text("Campaign \(snapshot.estimatedRemainingText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if snapshot.scenarioEstimatedRemainingText != "--" {
                    Text("Scenario \(snapshot.scenarioEstimatedRemainingText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, alignment: .trailing)
        }
    }

    private func signalGrid(_ snapshot: TrainingMonitorSnapshot) -> some View {
        LazyVGrid(columns: signalColumns, alignment: .leading, spacing: KuyuSpacing.sm) {
            MonitorSignalCell(title: "Runner", value: snapshot.eventStreamStatus, detail: "produced \(snapshot.eventAgeText) / received \(snapshot.receivedAgeText)", tone: freshnessTone(snapshot.eventStreamStatus))
            MonitorSignalCell(title: "Artifacts", value: snapshot.artifactMonitorStatus, detail: snapshot.artifactAgeText, tone: freshnessTone(snapshot.artifactMonitorStatus))
            MonitorSignalCell(title: "Loader", value: snapshot.artifactLoadStatus, detail: snapshot.artifactRootLabel, tone: loaderTone(snapshot.artifactLoadStatus))
            MonitorSignalCell(title: "Candidate", value: snapshot.candidateText, detail: "candidate \(snapshot.candidateAgeText) / work \(snapshot.workAgeText)", tone: .neutral)
            MonitorSignalCell(title: "Generation", value: snapshot.generationText, detail: snapshot.phase, tone: .neutral)
            MonitorSignalCell(title: "GPU Evidence", value: snapshot.acceleratorLabel, detail: snapshot.gpuEvidenceLabel, tone: gpuTone(snapshot.gpuEvidenceLabel))
            MonitorSignalCell(title: "Throughput", value: snapshot.throughputText, detail: snapshot.parallelismText, tone: .neutral)
            MonitorSignalCell(title: "Retention", value: "bounded", detail: snapshot.runLogRetentionText, tone: .info)
        }
    }

    private func alertStack(_ alerts: [TrainingMonitorSnapshot.Alert]) -> some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            ForEach(alerts) { alert in
                HStack(alignment: .top, spacing: KuyuSpacing.sm) {
                    Image(systemName: icon(alert.severity))
                        .foregroundStyle(color(alert.severity))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title)
                            .font(.caption.weight(.semibold))
                        Text(alert.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, KuyuSpacing.sm)
                .padding(.vertical, KuyuSpacing.xs)
                .background(color(alert.severity).opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: KuyuRadius.small, style: .continuous))
            }
        }
    }

    private func controlStrip(_ snapshot: TrainingMonitorSnapshot) -> some View {
        HStack(spacing: KuyuSpacing.sm) {
            Button {
                model.startLearningCampaign()
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(model.isLearningCampaignRunning || model.isRunning)
            .help("Start Learning Campaign")

            Button {
                model.continueLearningCampaignFromLastCheckpoint()
            } label: {
                Label("Continue", systemImage: "forward.fill")
            }
            .disabled(!model.canContinueLearningCampaign)
            .help("Continue from Last Checkpoint")

            Button(role: .destructive) {
                model.stopLearningCampaign()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!model.isLearningCampaignRunning)
            .help("Stop Learning Campaign")

            Divider()
                .frame(height: 18)

            Button {
                if model.learningCampaignMonitorEnabled {
                    model.stopLearningCampaignMonitoring()
                } else {
                    model.startLearningCampaignMonitoring()
                }
            } label: {
                Label(
                    model.learningCampaignMonitorEnabled ? "Monitor Off" : "Monitor On",
                    systemImage: model.learningCampaignMonitorEnabled ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
                )
            }
            .help(model.learningCampaignMonitorEnabled ? "Stop Artifact Monitor" : "Start Artifact Monitor")

            Button {
                model.reloadLearningCampaignArtifactsFromUI()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Reload Artifacts")

            Button {
                openArtifactRoot()
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .disabled(model.learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Reveal Artifact Root")

            Spacer(minLength: 0)

            StatusPill(snapshot.artifactMonitorStatus, tone: freshnessTone(snapshot.artifactMonitorStatus))
        }
        .controlSize(.small)
    }

    private func openArtifactRoot() {
        let path = model.learningCampaignArtifactDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        model.recordLearningCampaignArtifactReveal(path: path)
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        #endif
    }

    private func tone(_ health: TrainingMonitorSnapshot.Health) -> StatusPill.Tone {
        switch health {
        case .idle, .cancelled:
            return .neutral
        case .healthy, .complete:
            return .success
        case .attention, .rejected:
            return .warning
        case .stale, .failed:
            return .danger
        }
    }

    private func freshnessTone(_ value: String) -> StatusPill.Tone {
        switch value {
        case "live", "watching":
            return .success
        case "quiet", "pending":
            return .warning
        case "stale", "off":
            return .danger
        default:
            return .neutral
        }
    }

    private func loaderTone(_ value: String) -> StatusPill.Tone {
        switch value {
        case "loaded":
            return .success
        case "loading", "pending":
            return .warning
        case "stalled", "warning":
            return .danger
        default:
            return .neutral
        }
    }

    private func gpuTone(_ value: String) -> StatusPill.Tone {
        if value.hasPrefix("active") {
            return .success
        }
        if value.hasPrefix("ready") {
            return .warning
        }
        if value.hasPrefix("unavailable") {
            return .danger
        }
        return .neutral
    }

    private func icon(_ severity: TrainingMonitorSnapshot.AlertSeverity) -> String {
        switch severity {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "xmark.octagon"
        }
    }

    private func color(_ severity: TrainingMonitorSnapshot.AlertSeverity) -> Color {
        switch severity {
        case .info:
            return .accentColor
        case .warning:
            return .yellow
        case .critical:
            return .red
        }
    }
}

private struct MonitorSignalCell: View {
    let title: String
    let value: String
    let detail: String
    let tone: StatusPill.Tone

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: KuyuSpacing.xs) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                StatusPill(value, tone: tone)
            }
            Text(detail)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
