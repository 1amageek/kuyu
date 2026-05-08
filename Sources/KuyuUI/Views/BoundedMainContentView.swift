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
            "別ウィンドウで開きます",
            systemImage: "macwindow.on.rectangle",
            description: Text("シミュレーション、モニター、分析、レポートはサイドバーの「開く」から別ウィンドウで表示します。")
        )
    }
}
