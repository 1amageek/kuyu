import SwiftUI

struct BoundedToolbarContent: ToolbarContent {
    @Bindable var model: AppViewModel
    @Binding var showInspector: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            BoundedHeaderControlsView(model: model)
        }

        ToolbarItem(placement: .principal) {
            BoundedPrincipalToolbarView(model: model)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            BoundedHeaderToolsMenu(
                model: model,
                showInspector: $showInspector
            )
        }
    }
}

private struct BoundedPrincipalToolbarView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        if model.selectedWorkspace.showsPhaseStepper {
            TrainingPhaseStepperView(selection: $model.selectedTrainingPhase)
        } else {
            BoundedHeaderStatusView(model: model.simulationViewModel)
        }
    }
}

private struct TrainingPhaseStepperView: View {
    @Binding var selection: BoundedTrainingPhase

    var body: some View {
        Picker("Phase", selection: $selection) {
            ForEach(BoundedTrainingPhase.allCases) { phase in
                Text("\(phase.step). \(phase.title)").tag(phase)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(minWidth: 360)
    }
}

private struct BoundedHeaderControlsView: View {
    @Bindable var model: AppViewModel
    @State private var isConfirmingReset = false

    var body: some View {
        HStack(spacing: KuyuSpacing.xs) {
            runButton
            pauseButton
            stopButton
            resetButton
            stepButton
        }
        .confirmationDialog(
            "Reset workspace?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Clear Runs & Training State", role: .destructive) {
                model.simulationViewModel.resetSimulationPlayback()
                model.simulationViewModel.clearRuns()
                model.simulationViewModel.clearTrainingState()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears all runs and training state from this session. Artifacts on disk are not affected.")
        }
    }

    private var runButton: some View {
        // The toolbar play button means exactly one thing in every workspace:
        // start the learning campaign. Baseline runs live in the Run workspace.
        Button {
            model.simulationViewModel.startLearningCampaign()
        } label: {
            Image(systemName: "play.fill")
        }
        .disabled(model.simulationViewModel.isLearningCampaignRunning || model.simulationViewModel.isRunning)
        .help("Start Learning Campaign")
        .accessibilityLabel("Start Learning Campaign")
    }

    private var pauseButton: some View {
        Button {
            if model.simulationViewModel.isLoopRunning {
                model.simulationViewModel.pauseTrainingLoop()
            } else if model.simulationViewModel.isRunning {
                model.simulationViewModel.pauseRun()
            }
        } label: {
            Image(systemName: "pause.fill")
        }
        .disabled(!model.simulationViewModel.isRunning && !model.simulationViewModel.isLoopRunning)
        .help("Pause")
        .accessibilityLabel("Pause")
    }

    private var stopButton: some View {
        Button(role: .destructive) {
            if model.simulationViewModel.isLearningCampaignRunning {
                model.simulationViewModel.stopLearningCampaign()
            } else {
                model.simulationViewModel.stopRun()
            }
        } label: {
            Image(systemName: "stop.fill")
        }
        .disabled(!model.simulationViewModel.isLearningCampaignRunning && !model.simulationViewModel.isRunning)
        .help("Stop")
        .accessibilityLabel("Stop")
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            isConfirmingReset = true
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .help("Reset workspace (clears runs and training state)")
        .accessibilityLabel("Reset workspace")
    }

    private var stepButton: some View {
        Button {
            model.simulationViewModel.stepSimulationPlayback()
        } label: {
            Image(systemName: "forward.end.fill")
        }
        .help("Step Simulation Playback")
        .accessibilityLabel("Step Simulation Playback")
    }
}

private struct BoundedHeaderStatusView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        BoundedRunStatusChipsView(model: model)
            .padding(.horizontal, KuyuSpacing.sm)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: KuyuRadius.small, style: .continuous))
    }
}

private struct BoundedHeaderToolsMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: AppViewModel
    @Binding var showInspector: Bool

    var body: some View {
        Menu {
            // Only one project can be open at a time, so this is a status
            // readout, not a picker — a picker here would imply switching.
            Section("Project") {
                Text(model.selectedProjectName)
            }
            Divider()
            Button {
                showInspector.toggle()
            } label: {
                Label(showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
            }
            Button {
                openWindow(id: BoundedWindowID.report.rawValue)
            } label: {
                Label("Open Report", systemImage: "square.and.arrow.up")
            }
            Button {
                model.simulationViewModel.loadLearningCampaignArtifacts()
            } label: {
                Label("Reload Artifacts", systemImage: "arrow.clockwise")
            }
            Button {
                model.simulationViewModel.exportLogs()
            } label: {
                Label("Export Run Logs", systemImage: "doc.text.below.ecg")
            }
            .disabled(model.simulationViewModel.selectedRun == nil)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .help("Project, layout, and export tools")
        .accessibilityLabel("Header Tools")
    }
}
