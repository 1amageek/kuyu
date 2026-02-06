import SwiftUI

public struct SidebarView: View {
    public let mode: AppViewModel.Mode
    @Bindable public var simulationModel: SimulationViewModel
    @Bindable public var trainingModel: SimulationViewModel

    public init(mode: AppViewModel.Mode, simulationModel: SimulationViewModel, trainingModel: SimulationViewModel) {
        self.mode = mode
        self.simulationModel = simulationModel
        self.trainingModel = trainingModel
    }

    public var body: some View {
        switch mode {
        case .simulation:
            simulationSidebar
        case .training:
            trainingSidebar
        }
    }

    // MARK: - Simulation Sidebar

    private var simulationSidebar: some View {
        List(selection: $simulationModel.selectedRunID) {
            Section("Training Suite") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("KUY-ATT-1 (M1)")
                        .font(KuyuUITheme.titleFont(size: 14))
                        .foregroundStyle(KuyuUITheme.textPrimary)
                    Text("Attitude stabilization + swappability + HF stress")
                        .font(KuyuUITheme.bodyFont(size: 12))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                }
                .padding(.vertical, 6)
            }

            Section("Runs") {
                if simulationModel.runs.isEmpty {
                    Text("No runs yet")
                        .font(KuyuUITheme.bodyFont(size: 12))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                } else {
                    ForEach(simulationModel.runs) { run in
                        RunRowView(run: run)
                            .tag(run.id)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KuyuUITheme.panelBackground)
    }

    // MARK: - Training Sidebar

    private var trainingSidebar: some View {
        List(selection: $trainingModel.selectedRunID) {
            Section {
                ForEach(trainingModel.availableModels) { model in
                    HStack(spacing: 8) {
                        Text(model.name)
                            .font(KuyuUITheme.titleFont(size: 13))
                            .foregroundStyle(KuyuUITheme.textPrimary)
                        Spacer()
                        if model.id == trainingModel.selectedModelID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(KuyuUITheme.accent)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        trainingModel.selectModel(id: model.id)
                    }
                }
            } header: {
                HStack {
                    Text("Models")
                    Spacer()
                    Button(action: { trainingModel.createModel() }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Training Suite") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("KUY-ATT-1 (M1)")
                        .font(KuyuUITheme.titleFont(size: 14))
                        .foregroundStyle(KuyuUITheme.textPrimary)
                    Text("Attitude stabilization + swappability + HF stress")
                        .font(KuyuUITheme.bodyFont(size: 12))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                }
                .padding(.vertical, 6)
            }

            Section("Runs") {
                if trainingModel.runs.isEmpty {
                    Text("No runs yet")
                        .font(KuyuUITheme.bodyFont(size: 12))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                } else {
                    ForEach(trainingModel.runs) { run in
                        RunRowView(run: run)
                            .tag(run.id)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KuyuUITheme.panelBackground)
    }
}

#Preview("Simulation") {
    let buffer = UILoggingBootstrap.buffer
    let logStore = UILogStore(buffer: buffer)
    let simModel = SimulationViewModel(logStore: logStore)
    return SidebarView(mode: .simulation, simulationModel: simModel, trainingModel: simModel)
        .frame(width: 260, height: 520)
}

#Preview("Training") {
    let buffer = UILoggingBootstrap.buffer
    let logStore = UILogStore(buffer: buffer)
    let simModel = SimulationViewModel(logStore: logStore)
    return SidebarView(mode: .training, simulationModel: simModel, trainingModel: simModel)
        .frame(width: 260, height: 520)
}
