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
            projectDetail
        }
        .navigationTitle(model.currentProject?.package.manifest.name ?? "Bounded")
        .toolbar {
            BoundedToolbarContent(
                model: model,
                showInspector: $showInspector
            )
        }
        .alert(
            "Operation Failed",
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
        .alert(
            "Project Operation Failed",
            isPresented: Binding(
                get: { model.projectCreationError != nil },
                set: { presented in
                    if !presented { model.projectCreationError = nil }
                }
            ),
            presenting: model.projectCreationError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error)
        }
    }

    private var projectDetail: some View {
        GeometryReader { proxy in
            let layoutSize = QuantizedLayoutSize(proxy.size)
            HStack(spacing: 0) {
                BoundedMainContentView(model: model)
                    .frame(minWidth: 760, minHeight: 520)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector {
                    Divider()
                    BoundedInspectorView(model: model)
                        .frame(
                            minWidth: KuyuLayout.inspectorMin,
                            idealWidth: KuyuLayout.inspectorIdeal,
                            maxWidth: KuyuLayout.inspectorMax,
                            maxHeight: .infinity
                        )
                        .background(.bar)
                }
            }
            .onAppear {
                recordContentLayoutState(reason: "appear", layoutSize: layoutSize)
            }
            .onChange(of: showInspector) { _, _ in
                recordContentLayoutState(reason: "inspectorChanged", layoutSize: layoutSize)
            }
            .onChange(of: model.selectedWorkspace) { _, _ in
                recordContentLayoutState(reason: "workspaceChanged", layoutSize: layoutSize)
            }
            .onChange(of: model.currentProject?.package.manifest.projectID) { _, _ in
                recordContentLayoutState(reason: "projectChanged", layoutSize: layoutSize)
            }
            .onChange(of: layoutSize) { _, newValue in
                recordContentLayoutState(reason: "detailResized", layoutSize: newValue)
            }
        }
    }

    private func recordContentLayoutState(reason: String, layoutSize: QuantizedLayoutSize) {
        model.recordContentLayoutState(
            reason: reason,
            inspectorVisible: showInspector,
            detailWidth: layoutSize.width,
            detailHeight: layoutSize.height
        )
    }
}

private struct QuantizedLayoutSize: Equatable {
    let width: Int
    let height: Int

    init(_ size: CGSize) {
        width = Self.quantize(size.width)
        height = Self.quantize(size.height)
    }

    private static func quantize(_ value: CGFloat) -> Int {
        Int((value / 16).rounded() * 16)
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
