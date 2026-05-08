import SwiftUI
import KuyuCore

public struct RunDetailView: View {
    @Bindable var model: SimulationViewModel

    public var body: some View {
        if let run = model.selectedRun {
            List(selection: $model.selectedScenarioKey) {
                ForEach(run.scenarios) { scenario in
                    ScenarioRowView(scenario: scenario)
                        .tag(scenario.id as ScenarioKey?)
                }
            }
            .listStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                Text("No run selected")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Run the KUY-ATT-1 suite to see scenario details and charts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(KuyuSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

#Preview {
    RunDetailView(model: KuyuUIPreviewFactory.model())
        .frame(width: 520, height: 640)
}
