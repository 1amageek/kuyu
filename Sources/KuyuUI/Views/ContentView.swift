import SwiftUI

struct ContentView: View {
    @Bindable var model: SimulationViewModel
    @State private var showInspector = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            VSplitView {
                ScenarioDetailView(model: model)
                VStack(spacing: 8) {
                    suiteResultBand
                    HSplitView {
                        RunDetailView(model: model)
                            .frame(minWidth: 260, idealWidth: 340)
                        LogConsoleView(entries: model.logStore.entries, onClear: model.logStore.clear)
                            .frame(minWidth: 360, maxWidth: .infinity)
                    }
                }
                .frame(minHeight: 240)
            }
        }
        .inspector(isPresented: $showInspector) {
            InspectorView(model: model)
                .inspectorColumnWidth(min: 260, ideal: 320, max: 380)
        }
        .navigationTitle("KuyuUI")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: model.startTrainingLoop) {
                    Label("Run Loop", systemImage: "play.fill")
                }
                .disabled(model.isLoopRunning || model.isRunning)
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    if model.isLoopRunning || model.isRunning || model.isTraining {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(runStatusLabel)
                        .font(KuyuUITheme.bodyFont(size: 12))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(action: model.runBaseline) {
                    Label("Run Once", systemImage: "bolt.fill")
                }
                .disabled(model.isRunning || model.isLoopRunning)
            }
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    if model.isLoopRunning {
                        model.isLoopPaused ? model.resumeTrainingLoop() : model.pauseTrainingLoop()
                    } else {
                        model.pauseRun()
                    }
                }) {
                    let isPaused = model.isLoopRunning ? model.isLoopPaused : model.isPaused
                    Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                }
                .disabled(!(model.isRunning || model.isLoopRunning))
            }
            ToolbarItem(placement: .navigation) {
                Button(role: .destructive, action: {
                    model.isLoopRunning ? model.stopTrainingLoop() : model.stopRun()
                }) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!(model.isRunning || model.isLoopRunning))
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(action: model.exportLogs) {
                    Label("Export Logs", systemImage: "tray.and.arrow.down.fill")
                }
                .disabled(model.selectedRun == nil)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(action: model.exportTrainingDataset) {
                    Label("Export Dataset", systemImage: "square.and.arrow.down")
                }
                .disabled(model.selectedRun == nil)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(action: model.trainCoreModel) {
                    Label("Train Core", systemImage: "brain")
                }
                .disabled(model.isTraining)
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

    private var runStatusLabel: String {
        if model.isLoopRunning {
            return model.isLoopPaused ? "Loop paused" : "Loop running"
        }
        if model.isTraining {
            return "Training"
        }
        if model.isRunning {
            return "Running"
        }
        return "Idle"
    }

    private var suiteResultBand: some View {
        let run = model.selectedRun
        return HStack(spacing: 12) {
            Text("Suite Result")
                .font(KuyuUITheme.titleFont(size: 12))
                .foregroundStyle(KuyuUITheme.textPrimary)
            if let run {
                StatBadgeView(passed: run.output.summary.suitePassed)
                Text("Scenarios \(run.scenarios.count)")
                    .font(KuyuUITheme.bodyFont(size: 11))
                    .foregroundStyle(KuyuUITheme.textSecondary)
                if let best = model.loopBestScore {
                    Text("Best \(String(format: "%.3f", best))")
                        .font(KuyuUITheme.monoFont(size: 10))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                }
            } else {
                Text("No run selected")
                    .font(KuyuUITheme.bodyFont(size: 11))
                    .foregroundStyle(KuyuUITheme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(KuyuUITheme.panelBackground)
        .overlay(
            Rectangle()
                .stroke(KuyuUITheme.panelHighlight, lineWidth: 1)
        )
    }
}

#Preview {
    ContentView(model: KuyuUIPreviewFactory.model())
        .frame(width: 1280, height: 800)
}
