import SwiftUI

struct BoundedMainContentView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        switch model.selectedWorkspace {
        case .dashboard:
            DashboardWorkspaceView(model: model.simulationViewModel)
        case .training, .experimentDesign, .reinforcementLearning, .geneticLearning, .hybridIntegration, .environment:
            TrainingWorkspaceView(model: model)
        case .analysis, .report, .monitor:
            AuxiliaryWindowPlaceholderView()
        case .settings:
            SettingsWorkspaceView(model: model.simulationViewModel)
        case .system:
            SystemWorkspaceView(model: model.simulationViewModel)
        }
    }
}

private struct AuxiliaryWindowPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Opens in a separate window",
            systemImage: "macwindow.on.rectangle",
            description: Text("Simulation, Monitor, Analysis, and Report open in their own windows from the sidebar's “Open” section.")
        )
    }
}
