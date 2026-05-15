import KuyuMLX
import KuyuTraining
import SwiftUI

struct LaunchValidationView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    LabeledContent("Status", value: model.learningStarterProjectStatus)
                    LabeledContent("Source", value: sourceCheckpoint)
                    LabeledContent("Next Run", value: artifactRoot)
                    Button {
                        model.prepareStarterLearningProject()
                    } label: {
                        Label("Prepare Starter Project", systemImage: "sparkles")
                    }
                }
            } label: {
                Label("Starter Project", systemImage: "shippingbox")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    Picker("Launch Preset", selection: $model.learningCampaignPreset) {
                        ForEach(LearningCampaignRunPreset.allCases, id: \.self) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }

                    Picker("Autonomy Domain", selection: $model.learningCampaignAutonomyDomain) {
                        ForEach(AutonomousOperationDomain.allCases, id: \.self) { domain in
                            Text(domain.displayName).tag(domain)
                        }
                    }

                    Toggle("Use Machine-Optimized Parallelism", isOn: $model.learningCampaignAutoParallelism)

                    Button {
                        model.optimizeLearningCampaignParallelismForMachine()
                    } label: {
                        Label("Optimize for This Mac", systemImage: "cpu")
                    }

                    Button {
                        model.startLearningCampaign()
                    } label: {
                        Label("Start New Run", systemImage: "play.fill")
                    }
                    .disabled(model.isLearningCampaignRunning)

                    Button {
                        model.continueLearningCampaignFromLastCheckpoint()
                    } label: {
                        Label("Continue From Checkpoint", systemImage: "forward.end.fill")
                    }
                    .disabled(!model.canContinueLearningCampaign)

                    Button {
                        model.validateLearningCampaignLaunch()
                    } label: {
                        Label("Dry Run Validation", systemImage: "checkmark.seal")
                    }

                    Button {
                        model.estimateLearningCampaignCost()
                    } label: {
                        Label("Estimate Compute Cost", systemImage: "gauge")
                    }

                    Button {
                        model.saveLearningCampaignTemplate()
                    } label: {
                        Label("Save as Template", systemImage: "doc.badge.plus")
                    }

                    Button {
                        model.queueLearningCampaignRun()
                    } label: {
                        Label("Queue Run", systemImage: "tray.and.arrow.down")
                    }
                }
            } label: {
                Label("Launch Settings", systemImage: "paperplane")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    StatRow(label: "Source Checkpoint", value: sourceCheckpoint)
                    StatRow(label: "Artifact Root", value: artifactRoot)
                    StatRow(label: "Domain", value: model.learningCampaignAutonomyDomain.displayName)
                    StatRow(label: "Suites", value: model.learningCampaignSuites)
                    StatRow(label: "Quality Gate", value: "strict")
                    StatRow(label: "Machine", value: model.learningCampaignMachineCapacity.summary)
                    StatRow(label: "Readiness", value: model.learningCampaignReadiness.status.label)
                    Text(model.learningCampaignReadiness.message)
                        .font(.caption)
                        .foregroundStyle(readinessColor)
                    if let templateStatus = model.learningCampaignTemplateStatus {
                        StatRow(label: "Template", value: templateStatus)
                    }
                    if !model.learningCampaignQueuedRuns.isEmpty {
                        StatRow(label: "Queued Runs", value: "\(model.learningCampaignQueuedRuns.count)")
                    }
                    if let estimate = model.learningCampaignLaunchEstimate {
                        Divider()
                        StatRow(label: "Scale", value: estimate.scaleLabel)
                        StatRow(label: "Candidates", value: "\(estimate.candidateEvaluations)")
                        StatRow(label: "Regression Rollouts", value: "\(estimate.regressionRollouts)")
                        StatRow(label: "Regression Episodes", value: "\(estimate.regressionEpisodes)")
                        StatRow(label: "Parallelism", value: estimate.parallelismLabel)
                        StatRow(label: "Machine Slots", value: estimate.machineUtilizationLabel)
                        StatRow(label: "Retention", value: estimate.retention)
                    }
                    if let error = model.learningCampaignError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } label: {
                Label("Validation Preview", systemImage: "list.clipboard")
            }
        }
    }

    private var sourceCheckpoint: String {
        let value = model.learningCampaignSourceCheckpointPath
        guard !value.isEmpty else { return "missing" }
        return URL(fileURLWithPath: value).lastPathComponent
    }

    private var artifactRoot: String {
        let value = model.learningCampaignArtifactDirectory
        guard !value.isEmpty else { return "missing" }
        return URL(fileURLWithPath: value).lastPathComponent
    }

    private var readinessColor: Color {
        switch model.learningCampaignReadiness.status {
        case .idle:
            return .secondary
        case .ready:
            return .green
        case .blocked:
            return .orange
        }
    }
}

private extension AutonomousOperationDomain {
    var displayName: String {
        switch self {
        case .automotive:
            return "Automotive"
        case .groundRobot:
            return "Ground Robot"
        case .aerialDrone:
            return "Aerial Drone"
        case .manipulator:
            return "Manipulator"
        }
    }
}
