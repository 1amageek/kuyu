import SwiftUI

public struct ReportWindowContentView: View {
    @Bindable var model: SimulationViewModel
    @State private var showLogs: Bool = true

    public init(model: SimulationViewModel) {
        self.model = model
    }

    public var body: some View {
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
