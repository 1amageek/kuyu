import SwiftUI
import KuyuCore

struct RunDetailView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let run = model.selectedRun {
                List(selection: $model.selectedScenarioKey) {
                    ForEach(run.scenarios) { scenario in
                        ScenarioRowView(scenario: scenario)
                            .tag(scenario.id as ScenarioKey?)
                    }
                }
                .listStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No run selected")
                        .font(KuyuUITheme.titleFont(size: 14))
                        .foregroundStyle(KuyuUITheme.textPrimary)
                    Text("Run the KUY-ATT-1 suite to see scenario details and charts.")
                        .font(KuyuUITheme.bodyFont(size: 12))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                }
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.clear)
    }
}

#Preview {
    RunDetailView(model: KuyuUIPreviewFactory.model())
        .frame(width: 520, height: 640)
        .background(KuyuUITheme.background)
}
