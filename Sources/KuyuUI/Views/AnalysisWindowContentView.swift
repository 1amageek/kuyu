import SwiftUI

public struct AnalysisWindowContentView: View {
    @Bindable var model: SimulationViewModel
    @State private var showRuns: Bool = true

    public init(model: SimulationViewModel) {
        self.model = model
    }

    public var body: some View {
        CollapsibleSplitView(isExpanded: $showRuns) {
            ScrollView {
                VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
                    KeyTrainingChartsView(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(KuyuSpacing.xl)
            }
        } content: {
            ScrollView {
                RunListView(model: model)
                    .padding(KuyuSpacing.md)
            }
        } header: {
            Label("Runs", systemImage: "list.bullet")
        }
        .navigationTitle("Analysis")
    }
}
