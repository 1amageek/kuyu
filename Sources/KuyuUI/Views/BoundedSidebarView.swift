import SwiftUI

struct BoundedSidebarView: View {
    @Bindable var model: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List(selection: $model.selectedWorkspace) {
            Section("ライブ") {
                workspaceRow(.dashboard)
                workspaceRow(.training)
            }

            Section("結果") {
                workspaceRow(.analysis)
                workspaceRow(.report)
            }

            Section("システム") {
                workspaceRow(.monitor)
            }

            Section("ウィンドウ") {
                Button {
                    openWindow(id: BoundedWindowID.simulation.rawValue)
                } label: {
                    Label(BoundedWindowID.simulation.title, systemImage: BoundedWindowID.simulation.systemImage)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarBottom
        }
    }

    private func workspaceRow(_ workspace: BoundedWorkspace) -> some View {
        Label(workspace.title, systemImage: workspace.systemImage)
            .tag(workspace)
    }

    private var sidebarBottom: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            Divider()
            HStack {
                Button {
                    model.selectedWorkspace = .settings
                } label: {
                    Label(BoundedWorkspace.settings.title, systemImage: BoundedWorkspace.settings.systemImage)
                }

                Button {
                    model.selectedWorkspace = .system
                } label: {
                    Label(BoundedWorkspace.system.title, systemImage: BoundedWorkspace.system.systemImage)
                }
            }
            SystemStatusSummaryView(model: model.simulationViewModel)
        }
        .padding(KuyuSpacing.sm)
        .background(.bar)
    }
}
