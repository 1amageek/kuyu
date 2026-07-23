import Foundation
import SwiftUI

struct TrainingRunEvidenceView: View {
    let detail: TrainingRunDetailSnapshot
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                outcomeSection
                identitySection
                journalSection
                controlSection
            }
            .padding(.top, KuyuSpacing.sm)
        } label: {
            Label("Run Evidence", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
        }
    }

    private var identitySection: some View {
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
                    value:
                        "tier=\(detail.manifest.determinism.tier) "
                        + "seedBase=\(detail.manifest.determinism.mlxRandomSeedBase)",
                    compact: true
                )
                StatRow(
                    label: "Randomness",
                    value: detail.manifest.determinism.mlxRandomnessContractID,
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

    private var outcomeSection: some View {
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

    private var journalSection: some View {
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
                        StatRow(label: "Checkpoint", value: checkpoint.path, compact: true)
                    }
                }
            }
        } label: {
            Label("Journal", systemImage: "list.bullet.rectangle.portrait")
        }
    }

    private var controlSection: some View {
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
}
