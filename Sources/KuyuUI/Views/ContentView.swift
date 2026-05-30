import SwiftUI

public struct ContentView: View {
    @Bindable var model: AppViewModel
    @SceneStorage("showInspector") private var showInspector = true

    public init(model: AppViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.currentProject == nil {
                BoundedWelcomeView(model: model)
                    .frame(minWidth: 920, minHeight: 600)
            } else {
                projectWorkspace
            }
        }
        .onOpenURL { url in
            model.openURL(url)
        }
    }

    private var projectWorkspace: some View {
        NavigationSplitView {
            BoundedSidebarView(model: model)
                .navigationSplitViewColumnWidth(
                    min: KuyuLayout.sidebarMin,
                    ideal: KuyuLayout.sidebarIdeal,
                    max: KuyuLayout.sidebarMax
                )
        } detail: {
            BoundedMainContentView(model: model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .inspector(isPresented: $showInspector) {
            BoundedInspectorView(model: model)
                .inspectorColumnWidth(
                    min: KuyuLayout.inspectorMin,
                    ideal: 320,
                    max: 420
                )
        }
        .navigationTitle(model.currentProject?.package.manifest.name ?? "Bounded")
        .toolbar {
            BoundedToolbarContent(
                model: model,
                showInspector: $showInspector
            )
        }
        .alert(
            "Run Failed",
            isPresented: Binding(
                get: { model.simulationViewModel.runError != nil },
                set: { presented in
                    if !presented { model.simulationViewModel.runError = nil }
                }
            ),
            presenting: model.simulationViewModel.runError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error)
        }
    }
}

#Preview {
    let buffer = UILoggingBootstrap.buffer
    let logStore = UILogStore(buffer: buffer)
    let appModel = AppViewModel(logStore: logStore)
    return ContentView(model: appModel)
        .frame(minWidth: 1100, minHeight: 720)
        .frame(width: 1440, height: 900)
}
