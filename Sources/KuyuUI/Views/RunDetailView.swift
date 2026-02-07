import SwiftUI
import KuyuCore

public struct RunDetailView: View {
    @Bindable var model: SimulationViewModel

    public var body: some View {
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
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Run the KUY-ATT-1 suite to see scenario details and charts.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RunDetailView(model: KuyuUIPreviewFactory.model())
        .frame(width: 520, height: 640)
}
