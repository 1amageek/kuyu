import SwiftUI
import KuyuMLXCampaignContracts

struct TrainingArtifactsView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                if let state = model.learningCampaignState, !state.autonomyStages.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                            StatRow(label: "Progress", value: state.autonomyPipelineSummary)
                            ForEach(state.autonomyStages) { stage in
                                autonomyStageRow(stage)
                            }
                        }
                    } label: {
                        Label("Autonomy Pipeline", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                }

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

    private func autonomyStageRow(_ stage: LearningCampaignAutonomyStageState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
            StatusPill(stage.status, tone: autonomyTone(stage.status))
                .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.stageID)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(stage.kind) · gates \(stage.satisfiedGateCount) · evidence \(stage.requiredEvidenceCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !stage.failureReasons.isEmpty {
                Text(stage.failureReasons.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }

    private func autonomyTone(_ status: String) -> StatusPill.Tone {
        switch status {
        case "completed":
            return .success
        case "blocked":
            return .warning
        case "pending", "skipped":
            return .neutral
        default:
            return .neutral
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
