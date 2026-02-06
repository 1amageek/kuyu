import SwiftUI
import KuyuCore

public struct ContentView: View {
    @Bindable var model: AppViewModel
    @SceneStorage("showInspector") private var showInspector = true

    public init(model: AppViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(
                mode: model.currentMode,
                simulationModel: model.simulationViewModel,
                trainingModel: model.simulationViewModel
            )
        } detail: {
            detailView
        }
        .inspector(isPresented: $showInspector) {
            InspectorView(
                mode: model.currentMode,
                simulationModel: model.simulationViewModel,
                trainingModel: model.simulationViewModel
            )
        }
        .navigationTitle("Kuyu")
        .toolbar {
            // Left: Control buttons (mode-specific)
            ToolbarItemGroup(placement: .navigation) {
                switch model.currentMode {
                case .simulation:
                    simulationControlButtons
                case .training:
                    trainingControlButtons
                }
            }

            // Center: Status bar
            ToolbarItem(placement: .principal) {
                StatusBarView(
                    mode: model.currentMode,
                    simulationModel: model.simulationViewModel,
                    trainingModel: model.simulationViewModel
                )
            }

            // Right: Mode picker
            ToolbarItem(placement: .primaryAction) {
                Picker("Mode", selection: $model.currentMode) {
                    ForEach(AppViewModel.Mode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            // Right: Inspector toggle
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showInspector.toggle() }) {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
    }

    // MARK: - Toolbar Control Buttons

    @ViewBuilder
    private var simulationControlButtons: some View {
        let isRunning = model.simulationViewModel.isRunning || model.simulationViewModel.isLoopRunning
        let isPaused = model.simulationViewModel.isLoopRunning ? model.simulationViewModel.isLoopPaused : model.simulationViewModel.isPaused

        if isRunning {
            if isPaused {
                Button(action: {
                    if model.simulationViewModel.isLoopRunning {
                        model.simulationViewModel.resumeTrainingLoop()
                    } else {
                        model.simulationViewModel.pauseRun()
                    }
                }) {
                    Label("Resume", systemImage: "play.fill")
                }
            } else {
                Button(action: {
                    if model.simulationViewModel.isLoopRunning {
                        model.simulationViewModel.pauseTrainingLoop()
                    } else {
                        model.simulationViewModel.pauseRun()
                    }
                }) {
                    Label("Pause", systemImage: "pause.fill")
                }
            }

            Button(role: .destructive, action: {
                if model.simulationViewModel.isLoopRunning {
                    model.simulationViewModel.stopTrainingLoop()
                } else {
                    model.simulationViewModel.stopRun()
                }
            }) {
                Label("Stop", systemImage: "stop.fill")
            }
        } else {
            Button(action: model.simulationViewModel.runBaseline) {
                Label("Run", systemImage: "play.fill")
            }
        }
    }

    @ViewBuilder
    private var trainingControlButtons: some View {
        let trainingModel = model.simulationViewModel
        if trainingModel.isLoopRunning {
            if trainingModel.isLoopPaused {
                Button(action: trainingModel.resumeTrainingLoop) {
                    Label("Resume", systemImage: "play.fill")
                }
            } else {
                Button(action: trainingModel.pauseTrainingLoop) {
                    Label("Pause", systemImage: "pause.fill")
                }
            }
            Button(role: .destructive, action: trainingModel.stopTrainingLoop) {
                Label("Stop", systemImage: "stop.fill")
            }
        } else if trainingModel.isTraining {
            Button(action: {}) {
                Label("Training…", systemImage: "hourglass")
            }
            .disabled(true)
        } else {
            Button(action: trainingModel.runTraining) {
                Label("Run", systemImage: "play.fill")
            }
            .disabled(trainingModel.isRunning)
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch model.currentMode {
        case .simulation:
            simulationDetailView
        case .training:
            trainingDetailView
        }
    }

    @ViewBuilder
    private var simulationDetailView: some View {
        VSplitView {
            ScenarioDetailView(model: model.simulationViewModel)
                .fixedSize(horizontal: false, vertical: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 0) {
                suiteResultBand
                HSplitView {
                    RunDetailView(model: model.simulationViewModel)
                        .layoutPriority(1)
                    LogConsoleView(entries: model.simulationViewModel.logStore.entries, onClear: model.simulationViewModel.logStore.clear)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var trainingDetailView: some View {
        let trainingModel = model.simulationViewModel
        let scene = trainingModel.liveScene
        let robot = scene?.bodies.first
        let angles = robot.map { eulerAngles(from: $0.orientation) } ?? (roll: 0, pitch: 0, yaw: 0)
        let position = robot?.position ?? Axis3(x: 0, y: 0, z: 0)
        let renderInfo = trainingModel.renderAssetInfo()

        TrainingDashboardView(
            model: trainingModel,
            roll: angles.roll,
            pitch: angles.pitch,
            yaw: angles.yaw,
            position: position,
            renderInfo: renderInfo
        )
    }

    private func eulerAngles(from quaternion: QuaternionSnapshot) -> (roll: Double, pitch: Double, yaw: Double) {
        let w = quaternion.w
        let x = quaternion.x
        let y = quaternion.y
        let z = quaternion.z

        let sinr = 2 * (w * x + y * z)
        let cosr = 1 - 2 * (x * x + y * y)
        let roll = atan2(sinr, cosr)

        let sinp = 2 * (w * y - z * x)
        let pitch = abs(sinp) >= 1 ? (Double.pi / 2) * (sinp > 0 ? 1 : -1) : asin(sinp)

        let siny = 2 * (w * z + x * y)
        let cosy = 1 - 2 * (y * y + z * z)
        let yaw = atan2(siny, cosy)

        return (roll, pitch, yaw)
    }

    // MARK: - Suite Result Band

    private var suiteResultBand: some View {
        let run = model.simulationViewModel.selectedRun
        return HStack(spacing: 12) {
            Text("Suite Result")
                .font(KuyuUITheme.titleFont(size: 12))
                .foregroundStyle(KuyuUITheme.textPrimary)
            if let run {
                StatBadgeView(passed: run.output.summary.suitePassed)
                Text("Scenarios \(run.scenarios.count)")
                    .font(KuyuUITheme.bodyFont(size: 11))
                    .foregroundStyle(KuyuUITheme.textSecondary)
                if let best = model.simulationViewModel.loopBestScore {
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
    let buffer = UILoggingBootstrap.buffer
    let logStore = UILogStore(buffer: buffer)
    let appModel = AppViewModel(logStore: logStore)
    return ContentView(model: appModel)
        .frame(width: 1280, height: 800)
}
