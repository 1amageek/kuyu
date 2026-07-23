import SwiftUI

struct RunWorkspaceView: View {
    @Bindable var model: AppViewModel

    private var runModel: SimulationViewModel {
        model.simulationViewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.xl) {
                header
                campaignControls
                TrainingLaunchReviewView(model: runModel)
                LaunchValidationView(model: runModel)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(KuyuSpacing.xl)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            Text("Run")
                .font(.title2.weight(.semibold))
            Text("Validate, estimate, and launch the learning campaign designed in Design.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var campaignControls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                HStack(spacing: KuyuSpacing.sm) {
                    Button {
                        runModel.startLearningCampaign()
                    } label: {
                        Label("Start Campaign", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(runModel.isRunning || runModel.isLearningCampaignRunning)

                    Button {
                        runModel.continueLearningCampaignFromLastCheckpoint()
                    } label: {
                        Label("Continue From Checkpoint", systemImage: "forward.end.fill")
                    }
                    .disabled(!runModel.canContinueLearningCampaign)

                    Button(role: .destructive) {
                        runModel.stopLearningCampaign()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(!runModel.isLearningCampaignRunning)
                }

                ProgressView(value: runModel.learningCampaignProgressFraction, total: 1)

                HStack(spacing: KuyuSpacing.sm) {
                    Text("Phase: \(runModel.learningCampaignCurrentPhase)")
                    if let event = runModel.learningCampaignLatestEvent {
                        Text(event)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let error = runModel.learningCampaignError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("Campaign", systemImage: "paperplane")
                .font(.headline)
        }
    }

}

private struct TrainingLaunchReviewView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
            launchChecklist
            HStack(alignment: .top, spacing: KuyuSpacing.lg) {
                launchArtifacts
                launchEstimate
                launchPolicy
            }
        }
    }

    private var launchChecklist: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                checklistRow(
                    "Resource Estimate",
                    status: model.learningCampaignLaunchEstimate == nil ? "Not run" : "OK",
                    tone: model.learningCampaignLaunchEstimate == nil ? .warning : .success
                )
                checklistRow(
                    "Dry Run Validation",
                    status: model.learningCampaignReadiness.status.label,
                    tone: readinessTone
                )
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("Checklist", systemImage: "checklist")
                .font(.headline)
        }
    }

    private var launchArtifacts: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Source Checkpoint", value: compactPath(model.learningCampaignSourceCheckpointPath))
                StatRow(label: "Artifact Root", value: compactPath(model.learningCampaignArtifactDirectory))
                StatRow(label: "Retention", value: model.learningCampaignCompactRetention ? "compact" : "full")
                StatRow(label: "Validation", value: model.learningCampaignReadiness.status.label)
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("Artifact", systemImage: "shippingbox")
                .font(.headline)
        }
    }

    private var launchEstimate: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                if let estimate = model.learningCampaignLaunchEstimate {
                    StatRow(label: "Scale", value: estimate.scaleLabel)
                    StatRow(label: "Candidates", value: "\(estimate.candidateEvaluations)")
                    StatRow(label: "Regression Rollouts", value: "\(estimate.regressionRollouts)")
                    StatRow(label: "Regression Episodes", value: "\(estimate.regressionEpisodes)")
                    StatRow(label: "Parallelism", value: estimate.parallelismLabel)
                } else {
                    Text("Run “Estimate Compute Cost” to see candidate, rollout, and episode counts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("Run Scale", systemImage: "ruler")
                .font(.headline)
        }
    }

    private var launchPolicy: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Quality Gate", value: "strict")
                StatRow(label: "Task Pass Rate", value: "1.0 required")
                StatRow(label: "Checkpoint", value: "accepted only")
                StatRow(label: "Regression", value: "task profile")
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("Acceptance Policy", systemImage: "checkmark.seal")
                .font(.headline)
        }
    }

    private func checklistRow(
        _ title: String,
        status: String,
        tone: StatusPill.Tone
    ) -> some View {
        HStack(spacing: KuyuSpacing.sm) {
            Image(systemName: tone == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(tone == .success ? .green : .orange)
            Text(title)
                .font(.callout)
            Spacer(minLength: 0)
            StatusPill(status, tone: tone)
        }
    }

    private var readinessTone: StatusPill.Tone {
        switch model.learningCampaignReadiness.status {
        case .idle:
            return .warning
        case .ready:
            return .success
        case .blocked:
            return .danger
        }
    }

    private func compactPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "missing" }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }
}
