import SwiftUI

struct DashboardWorkspaceView: View {
    @Bindable var model: SimulationViewModel
    @State private var showBottomPanel: Bool = true

    var body: some View {
        CollapsibleSplitView(isExpanded: $showBottomPanel) {
            ScrollView {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    CurrentRunSummaryView(model: model)

                    HStack(alignment: .top, spacing: KuyuSpacing.md) {
                        KeyTrainingChartsView(model: model)
                            .frame(maxWidth: .infinity)

                        VStack(spacing: KuyuSpacing.md) {
                            RunQueueView(model: model)
                            CheckpointSummaryView(model: model)
                        }
                        .frame(width: 320)
                    }
                }
                .padding(KuyuSpacing.md)
            }
        } content: {
            HStack(spacing: 0) {
                ScrollView {
                    RunListView(model: model)
                        .padding(KuyuSpacing.sm)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                ScrollView {
                    LogSummaryView(model: model)
                        .padding(KuyuSpacing.sm)
                }
                .frame(minWidth: 320, idealWidth: 480, maxWidth: 600, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        } header: {
            Label("Runs & Logs", systemImage: "list.bullet.rectangle")
                .font(.callout.weight(.semibold))
        }
    }
}
