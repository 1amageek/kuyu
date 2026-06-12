import SwiftUI

struct BoundedInspectorView: View {
    @Bindable var model: AppViewModel

    private var trainingModel: SimulationViewModel {
        model.simulationViewModel
    }

    var body: some View {
        Group {
            switch model.selectedWorkspace {
            case .dashboard:
                RunInspectorView(model: model)
            case .design, .run:
                trainingInspector
            case .results:
                AnalysisInspectorView(model: trainingModel)
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
            }
            .padding(KuyuSpacing.md)
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
