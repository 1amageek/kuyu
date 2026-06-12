import SwiftUI

public struct ReportWindowContentView: View {
    @Bindable var model: AppViewModel

    public init(model: AppViewModel) {
        self.model = model
    }

    public var body: some View {
        if model.currentProject == nil {
            ContentUnavailableView(
                "No Project Open",
                systemImage: "folder.badge.questionmark",
                description: Text("Open or create a project to generate a learning report.")
            )
            .navigationTitle("Report")
        } else {
            ReportWindowBody(model: model.simulationViewModel)
        }
    }
}

private struct ReportWindowBody: View {
    @Bindable var model: SimulationViewModel
    @State private var showLogs: Bool = true

    var body: some View {
        CollapsibleSplitView(isExpanded: $showLogs) {
            ScrollView {
                VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
                    header
                    KeyTrainingChartsView(model: model)
                    CheckpointSummaryView(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(KuyuSpacing.xl)
            }
        } content: {
            ScrollView {
                LogSummaryView(model: model)
                    .padding(KuyuSpacing.md)
            }
        } header: {
            Label("Logs", systemImage: "doc.text")
        }
        .navigationTitle("Report")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ReportExportMenu(model: model)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            Text("Bounded Learning Report")
                .font(.largeTitle.weight(.semibold))
            Text("This report is generated from typed campaign, regression, and checkpoint artifacts.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ReportExportMenu: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        Menu {
            ForEach(ReportExportFormat.allCases) { format in
                Button {
                    model.exportLearningReport(format: format)
                } label: {
                    Label(format.rawValue, systemImage: "square.and.arrow.up")
                }
            }
            if let status = model.reportExportStatus {
                Divider()
                Text(status)
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .help("Export the current report")
        .accessibilityLabel("Export Report")
    }
}
