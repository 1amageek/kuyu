import SwiftUI

struct BoundedInspectorView: View {
    @Bindable var model: AppViewModel

    private var trainingModel: SimulationViewModel {
        model.simulationViewModel
    }

    var body: some View {
        Group {
            switch model.selectedWorkspace {
            case .dashboard, .report:
                RunInspectorView(model: model)
            case .analysis:
                analysisInspector
            case .training,
                 .experimentDesign,
                 .reinforcementLearning,
                 .geneticLearning,
                 .hybridIntegration,
                 .environment:
                trainingInspector
            case .monitor:
                managementInspector(
                    title: "Monitor Inspector",
                    subtitle: "Local runtime summary",
                    systemImage: "chart.line.uptrend.xyaxis",
                    rows: [
                        ("Campaign", trainingModel.isLearningCampaignRunning ? "running" : "idle"),
                        ("Workers", "\(trainingModel.learningCampaignWorkers)"),
                        ("Progress", String(format: "%.0f%%", trainingModel.learningCampaignProgressFraction * 100)),
                        ("Logs", "\(trainingModel.logStore.entries.count)")
                    ]
                )
            case .settings:
                managementInspector(
                    title: "Settings Inspector",
                    subtitle: "Application configuration scope",
                    systemImage: "gearshape",
                    rows: [
                        ("Project", model.selectedProjectName),
                        ("Environment", model.selectedEnvironmentName),
                        ("Storage", trainingModel.learningCampaignArtifactDirectory.isEmpty ? "not selected" : "selected"),
                        ("Logging", "enabled")
                    ]
                )
            case .system:
                managementInspector(
                    title: "System Inspector",
                    subtitle: "Local runtime summary",
                    systemImage: "desktopcomputer",
                    rows: [
                        ("Campaign", trainingModel.isLearningCampaignRunning ? "running" : "idle"),
                        ("Monitor", trainingModel.learningCampaignMonitorEnabled ? "watching" : "stopped"),
                        ("Readiness", trainingModel.learningCampaignReadiness.status.label),
                        ("Runs", "\(trainingModel.runs.count)")
                    ]
                )
            }
        }
        .controlSize(.small)
    }

    private var trainingInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                trainingSummary
                runtimeSummary
                LaunchValidationView(model: trainingModel)
            }
            .padding(KuyuSpacing.md)
        }
    }

    private var analysisInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                campaignStatistics
                sampleStatistics
            }
            .padding(KuyuSpacing.md)
        }
    }

    private var campaignStatistics: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(
                    label: "Status",
                    value: trainingModel.learningCampaignState?.statusLabel ?? "--",
                    compact: true
                )
                StatRow(
                    label: "Accepted",
                    value: trainingModel.learningCampaignState
                        .map { "\($0.acceptedCount)/\($0.seedCount)" } ?? "--",
                    compact: true
                )
                StatRow(
                    label: "Best Delta",
                    value: trainingModel.learningCampaignState?.bestDelta
                        .map { String(format: "%+.4f", $0) } ?? "--",
                    compact: true
                )
                StatRow(
                    label: "Runs",
                    value: "\(trainingModel.runs.count)",
                    compact: true
                )
            }
        } label: {
            Label("Campaign", systemImage: "chart.bar.doc.horizontal")
        }
    }

    private var sampleStatistics: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Reward", value: "\(trainingModel.rewardAverageSamples.count)", compact: true)
                StatRow(label: "Loss", value: "\(trainingModel.trainingLossSamples.count)", compact: true)
                StatRow(label: "Loop Score", value: "\(trainingModel.loopScoreSamples.count)", compact: true)
                StatRow(label: "Pass Rate", value: "\(trainingModel.passRateSamples.count)", compact: true)
            }
        } label: {
            Label("Samples", systemImage: "square.stack.3d.up")
        }
    }

    private var trainingSummary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Phase", value: model.selectedTrainingPhase.title, compact: true)
                StatRow(label: "Strategy", value: trainingModel.learningStrategySelection.title, compact: true)
                StatRow(label: "Preset", value: trainingModel.learningCampaignPreset.rawValue, compact: true)
                StatRow(label: "Suites", value: trainingModel.learningCampaignSuites, compact: true)
                StatRow(label: "Population", value: "\(trainingModel.learningCampaignPopulation)", compact: true)
                StatRow(label: "Safety Budget", value: "\(trainingModel.learningCampaignGenerations)", compact: true)
            }
        } label: {
            Label("Training Inspector", systemImage: "sidebar.trailing")
        }
    }

    private var runtimeSummary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Template", value: trainingModel.learningCampaignPreset.rawValue, compact: true)
                StatRow(label: "Environment", value: trainingModel.taskMode.rawValue, compact: true)
                StatRow(label: "Seed", value: "\(trainingModel.learningCampaignSeedCount)", compact: true)
                StatRow(label: "Compute", value: trainingModel.determinismSelection.rawValue, compact: true)
                StatRow(
                    label: "Max Steps",
                    value: trainingModel.learningCampaignLaunchEstimate?.regressionEpisodes.formatted() ?? "--",
                    compact: true
                )
            }
        } label: {
            Label("Runtime Summary", systemImage: "stopwatch")
        }
    }

    private func managementInspector(
        title: String,
        subtitle: String,
        systemImage: String,
        rows: [(String, String)]
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                GroupBox {
                    VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                        ForEach(rows, id: \.0) { row in
                            StatRow(label: row.0, value: row.1, compact: true)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(title, systemImage: systemImage)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(KuyuSpacing.md)
        }
    }
}
