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
            BoundedWorkspaceActionToolbarView(model: model)
            BoundedHeaderToolsMenu(
                model: model,
                showInspector: $showInspector
            )
        }
    }
}

private struct BoundedWorkspaceActionToolbarView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        if model.selectedWorkspace == .report {
            ReportExportMenu(model: model.simulationViewModel)
        }
    }
}

private struct ReportExportMenu: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        Menu {
            ForEach(ReportExportFormat.allCases) { format in
                Button {
                    model.exportLearningReport(format: format)
                } label: {
                    Label(format.rawValue, systemImage: "square.and.arrow.up")
                }
            }
            if let status = model.reportExportStatus {
                Divider()
                Text(status)
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .help("Export the current report")
        .accessibilityLabel("Export Report")
    }
}

private struct BoundedPrincipalToolbarView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        if model.selectedWorkspace.isTrainingWorkspace {
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

    var body: some View {
        HStack(spacing: KuyuSpacing.xs) {
            runButton
            pauseButton
            stopButton
            resetButton
            stepButton
        }
        .controlSize(.small)
        .padding(.horizontal, KuyuSpacing.xs)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: KuyuRadius.small, style: .continuous))
    }

    private var runButton: some View {
        Button {
            if model.selectedWorkspace == .dashboard || model.selectedWorkspace.isTrainingWorkspace {
                model.simulationViewModel.startLearningCampaign()
            } else {
                model.simulationViewModel.runBaseline()
            }
        } label: {
            Image(systemName: "play.fill")
        }
        .disabled(model.simulationViewModel.isLearningCampaignRunning || model.simulationViewModel.isRunning)
        .help("Run")
        .accessibilityLabel("Run")
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
        Button {
            model.simulationViewModel.resetSimulationPlayback()
            model.simulationViewModel.clearRuns()
            model.simulationViewModel.clearTrainingState()
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .help("Reset")
        .accessibilityLabel("Reset")
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
            Picker("Project", selection: $model.selectedProjectName) {
                ForEach(model.availableProjectNames, id: \.self) { projectName in
                    Text(projectName).tag(projectName)
                }
            }
            Picker("Environment", selection: $model.selectedEnvironmentName) {
                Text("QuadLift-v1").tag("QuadLift-v1")
                Text("SinglePropLift-v1").tag("SinglePropLift-v1")
                Text("Attitude-v1").tag("Attitude-v1")
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
            Divider()
            Button {
                model.selectedWorkspace = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button {
                model.selectedWorkspace = .system
            } label: {
                Label("System", systemImage: "server.rack")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .help("Project, environment, layout, export, and settings")
        .accessibilityLabel("Header Tools")
    }
}
