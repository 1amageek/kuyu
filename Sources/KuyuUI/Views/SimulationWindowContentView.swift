import SwiftUI

public struct SimulationWindowContentView: View {
    @Bindable var model: AppViewModel

    public init(model: AppViewModel) {
        self.model = model
    }

    public var body: some View {
        if model.currentProject == nil {
            ContentUnavailableView(
                "No Project Open",
                systemImage: "folder.badge.questionmark",
                description: Text("Open or create a project to use the simulation window.")
            )
            .navigationTitle("Simulation")
        } else {
            SimulationWorkbenchView(model: model.simulationViewModel)
        }
    }
}
