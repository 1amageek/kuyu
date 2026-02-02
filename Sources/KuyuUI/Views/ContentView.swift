import SwiftUI

struct ContentView: View {
    @Bindable var model: SimulationViewModel
    @State private var showInspector = true
    private let sidebarWidth: CGFloat = 260
    private let inspectorWidth: CGFloat = 320

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            VSplitView {
                HSplitView {
                    RunDetailView(model: model)
                        .frame(minWidth: 220, maxWidth: 320)
                    ScenarioDetailView(model: model)
                        .frame(minWidth: 420,
                               idealWidth: 530,
                               maxWidth: .infinity)
                }
                LogConsoleView(entries: model.logStore.entries, onClear: model.logStore.clear)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 180,
                        idealHeight: 220,
                        maxHeight: 320)
            }
            .frame(maxWidth:560)
        }
        .inspector(isPresented: $showInspector) {
            InspectorView(model: model)
                .inspectorColumnWidth(min: 260, ideal: 320, max: 380)
        }
        .navigationTitle("KuyuUI")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: model.runBaseline) {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(model.isRunning)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(action: model.exportLogs) {
                    Label("Export Logs", systemImage: "tray.and.arrow.down.fill")
                }
                .disabled(model.selectedRun == nil)
            }
            ToolbarItem(placement: .navigation) {
                Button(action: { showInspector.toggle() }) {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .destructive, action: model.clearRuns) {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(model.runs.isEmpty)
            }
        }
    }
}

#Preview {
    ContentView(model: KuyuUIPreviewFactory.model())
        .frame(height: 660)
}
