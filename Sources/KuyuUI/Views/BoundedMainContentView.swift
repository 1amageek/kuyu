import SwiftUI

struct BoundedMainContentView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        switch model.selectedWorkspace {
        case .dashboard:
            DashboardWorkspaceView(model: model.simulationViewModel)
        case .runs:
            TrainingRunsWorkspaceView(model: model.trainingRunsViewModel)
        case .experimentDesign, .reinforcementLearning, .geneticLearning, .hybridIntegration, .environment:
            TrainingWorkspaceView(model: model)
        case .settings:
            SettingsWorkspaceView(model: model.simulationViewModel)
        case .system:
            SystemWorkspaceView(model: model.simulationViewModel)
        }
    }
}

