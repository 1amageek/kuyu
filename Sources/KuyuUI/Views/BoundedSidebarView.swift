import SwiftUI

struct BoundedSidebarView: View {
    @Bindable var model: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List(selection: $model.selectedWorkspace) {
            Section("Workspace") {
                workspaceRow(.dashboard)
                workspaceRow(.design)
                workspaceRow(.run)
                workspaceRow(.results)
            }

            Section("Open") {
                windowButton(.simulation)
                windowButton(.report)
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

    private func windowButton(_ windowID: BoundedWindowID) -> some View {
        Button {
            openWindow(id: windowID.rawValue)
        } label: {
            Label(windowID.title, systemImage: windowID.systemImage)
        }
    }

    private var sidebarBottom: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            Divider()
            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
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
