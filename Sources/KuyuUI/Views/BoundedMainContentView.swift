import SwiftUI

struct BoundedMainContentView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        switch model.selectedWorkspace {
        case .dashboard:
            DashboardWorkspaceView(model: model.simulationViewModel)
        case .design:
            TrainingWorkspaceView(model: model)
        case .run:
            RunWorkspaceView(model: model)
        case .results:
            ResultsWorkspaceView(model: model)
        case .system:
            SystemWorkspaceView(model: model.simulationViewModel)
        }
    }
}
