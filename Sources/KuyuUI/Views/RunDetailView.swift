import SwiftUI
import kuyu

struct RunDetailView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let run = model.selectedRun {
                if model.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running…")
                            .font(KuyuUITheme.bodyFont(size: 12))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                }
                RunSummaryView(run: run)

                List(selection: $model.selectedScenarioKey) {
                    ForEach(run.scenarios) { scenario in
                        ScenarioRowView(scenario: scenario)
                            .tag(scenario.id as ScenarioKey?)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(KuyuUITheme.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No run selected")
                        .font(KuyuUITheme.titleFont(size: 18))
                        .foregroundStyle(KuyuUITheme.textPrimary)
                    Text("Run the KUY-ATT-1 suite to see scenario details and charts.")
                        .font(KuyuUITheme.bodyFont(size: 13))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                }
                .padding(16)
                .background(KuyuUITheme.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
        }
        .padding(16)
        .background(Color.clear)
    }
}

#Preview {
    RunDetailView(model: KuyuUIPreviewFactory.model())
        .frame(width: 520, height: 640)
        .background(KuyuUITheme.background)
}
