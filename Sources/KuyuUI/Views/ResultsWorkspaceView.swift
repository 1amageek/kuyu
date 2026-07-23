import SwiftUI

struct ResultsWorkspaceView: View {
    @Bindable var model: AppViewModel
    @State private var scope: Scope = .session

    private enum Scope: String, CaseIterable, Identifiable {
        case session
        case archive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .session: return "Session"
            case .archive: return "Archive"
            }
        }
    }

    private var resultsModel: SimulationViewModel {
        model.simulationViewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            scopePicker
            Divider()
            switch scope {
            case .session:
                sessionResults
            case .archive:
                TrainingRunsWorkspaceView(model: model.trainingRunsViewModel)
            }
        }
    }

    private var scopePicker: some View {
        HStack {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)
            Spacer()
        }
        .padding(KuyuSpacing.sm)
    }

    @ViewBuilder
    private var sessionResults: some View {
        if let campaignState = resultsModel.learningCampaignState {
            CampaignSessionResultsView(model: resultsModel, state: campaignState)
        } else if resultsModel.runs.isEmpty {
            ContentUnavailableView(
                "No runs yet",
                systemImage: "tray",
                description: Text("Launch a campaign from Run or a simulation from Simulate to inspect results here.")
            )
        } else {
            HSplitView {
                runList
                    .frame(minWidth: 220, maxWidth: 320)
                RunDetailView(model: resultsModel)
                    .frame(minWidth: 240, maxWidth: 380)
                ScenarioDetailView(model: resultsModel)
                    .frame(minWidth: 460, maxWidth: .infinity)
            }
            .onChange(of: resultsModel.selectedRunID) { _, _ in
                // Reset scenario selection so the detail defaults to the new run's first scenario.
                resultsModel.selectedScenarioKey = nil
            }
        }
    }

    private var runList: some View {
        List(selection: Bindable(resultsModel).selectedRunID) {
            ForEach(resultsModel.runs) { run in
                RunRowView(run: run)
                    .tag(run.id as UUID?)
            }
        }
    }
}

private struct CampaignSessionResultsView: View {
    @Bindable var model: SimulationViewModel
    let state: LearningCampaignRunStoreState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
                header
                summary
                HStack(alignment: .top, spacing: KuyuSpacing.lg) {
                    EvolutionFitnessChartView(state: state)
                    PolicyLineageGraphView(state: state)
                }
                evidence
                failures
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(KuyuSpacing.xl)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                Text("Campaign Result")
                    .font(.title2.weight(.semibold))
                Text(state.task)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(state.statusLabel, tone: statusTone)
        }
    }

    private var summary: some View {
        GroupBox {
            HStack(alignment: .top, spacing: KuyuSpacing.xl) {
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    StatRow(label: "Accepted", value: "\(state.acceptedCount)/\(state.seedCount)")
                    StatRow(label: "Validation", value: state.validationLabel)
                    StatRow(label: "Suites", value: state.suiteSummary)
                }
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    StatRow(label: "Best Fitness", value: formatted(state.bestFitness))
                    StatRow(label: "Fitness Delta", value: formatted(state.bestFitnessDeltaFromInitial, signed: true))
                    StatRow(label: "Task Pass", value: percentage(state.bestTaskPassRate))
                }
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    StatRow(label: "Generations", value: "\(state.completedGenerationCount)/\(state.plannedGenerationCount)")
                    StatRow(label: "Candidates", value: "\(state.liveCandidateEvaluationCount)/\(state.plannedCandidateEvaluationCount)")
                    StatRow(label: "Parallelism", value: state.actualParallelismLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Outcome", systemImage: "chart.bar.xaxis")
        }
    }

    private var evidence: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                LabeledContent("Artifact Root") {
                    Text(state.artifactDirectory.path)
                        .textSelection(.enabled)
                }
                LabeledContent("Final Checkpoint") {
                    Text(state.finalCheckpoint ?? "No checkpoint accepted")
                        .textSelection(.enabled)
                }
                LabeledContent("Accelerator") {
                    Text(state.latestAcceleratorDevice ?? "--")
                }
            }
            .font(.callout)
        } label: {
            Label("Evidence", systemImage: "shippingbox")
        }
    }

    private var failures: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                if state.failureReasons.isEmpty {
                    Text("No failure reasons recorded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(state.failureReasons.enumerated()), id: \.offset) { _, reason in
                        Text(reason)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                if let error = model.learningCampaignError {
                    Divider()
                    Text(error)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Failures", systemImage: "exclamationmark.triangle")
        }
    }

    private var statusTone: StatusPill.Tone {
        switch state.statusLabel.lowercased() {
        case "succeeded", "completed": return .success
        case "failed", "cancelled", "rejected": return .warning
        case "running", "started": return .info
        default: return .neutral
        }
    }

    private func formatted(_ value: Double?, signed: Bool = false) -> String {
        guard let value else { return "--" }
        return String(format: signed ? "%+.3f" : "%.3f", value)
    }

    private func percentage(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f%%", value * 100)
    }
}
