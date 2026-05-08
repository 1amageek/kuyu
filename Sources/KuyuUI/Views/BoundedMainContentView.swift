import SwiftUI

struct BoundedMainContentView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        switch model.selectedWorkspace {
        case .dashboard:
            DashboardWorkspaceView(model: model.simulationViewModel)
        case .training, .experimentDesign, .reinforcementLearning, .geneticLearning, .hybridIntegration, .environment:
            TrainingWorkspaceView(model: model)
        case .analysis:
            AnalysisWindowContentView(model: model.simulationViewModel)
        case .report:
            ReportWindowContentView(model: model.simulationViewModel)
        case .monitor:
            MonitorWindowContentView(model: model.simulationViewModel)
        case .settings:
            SettingsWorkspaceView(model: model.simulationViewModel)
        case .system:
            SystemWorkspaceView(model: model.simulationViewModel)
        }
    }
}
