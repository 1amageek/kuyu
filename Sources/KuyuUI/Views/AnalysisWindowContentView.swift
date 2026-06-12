import SwiftUI

public struct AnalysisWindowContentView: View {
    @Bindable var model: SimulationViewModel
    @State private var showInspector: Bool = true

    public init(model: SimulationViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            runsSidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } content: {
            RunDetailView(model: model)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 380)
                .navigationTitle("Scenarios")
        } detail: {
            ScenarioDetailView(model: model)
                .frame(minWidth: 480, minHeight: 360)
        }
        .onChange(of: model.selectedRunID) { _, _ in
            // Reset scenario selection so the detail defaults to the new run's first scenario.
            model.selectedScenarioKey = nil
        }
        .inspector(isPresented: $showInspector) {
            AnalysisInspectorView(model: model)
                .inspectorColumnWidth(
                    min: KuyuLayout.inspectorMin,
                    ideal: 320,
                    max: 420
                )
        }
        .navigationTitle("Analysis")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help(showInspector ? "Hide Inspector" : "Show Inspector")
                .accessibilityLabel(showInspector ? "Hide Inspector" : "Show Inspector")
            }
        }
    }

    @ViewBuilder
    private var runsSidebar: some View {
        if model.runs.isEmpty {
            ContentUnavailableView(
                "No runs yet",
                systemImage: "tray",
                description: Text("Run a simulation or training campaign to inspect its scenarios here.")
            )
        } else {
            List(selection: $model.selectedRunID) {
                ForEach(model.runs) { run in
                    RunRowView(run: run)
                        .tag(run.id as UUID?)
                }
            }
            .navigationTitle("Runs")
        }
    }
}

private struct AnalysisInspectorView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                campaignStatistics
                sampleStatistics
            }
            .padding(KuyuSpacing.md)
        }
        .controlSize(.small)
    }

    private var campaignStatistics: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Status", value: model.learningCampaignState?.statusLabel ?? "--", compact: true)
                StatRow(
                    label: "Accepted",
                    value: model.learningCampaignState.map { "\($0.acceptedCount)/\($0.seedCount)" } ?? "--",
                    compact: true
                )
                StatRow(
                    label: "Best Delta",
                    value: model.learningCampaignState?.bestDelta.map { String(format: "%+.4f", $0) } ?? "--",
                    compact: true
                )
                StatRow(label: "Runs", value: "\(model.runs.count)", compact: true)
            }
        } label: {
            Label("Campaign", systemImage: "chart.bar.doc.horizontal")
        }
    }

    private var sampleStatistics: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Reward Samples", value: "\(model.rewardAverageSamples.count)", compact: true)
                StatRow(label: "Loss Samples", value: "\(model.trainingLossSamples.count)", compact: true)
                StatRow(label: "Loop Score Samples", value: "\(model.loopScoreSamples.count)", compact: true)
                StatRow(label: "Pass Rate Samples", value: "\(model.passRateSamples.count)", compact: true)
            }
        } label: {
            Label("Samples", systemImage: "square.stack.3d.up")
        }
    }
}
