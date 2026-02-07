import SwiftUI

public struct InspectorView: View {
    public let mode: AppViewModel.Mode
    @Bindable public var simulationModel: SimulationViewModel
    @Bindable public var trainingModel: SimulationViewModel

    public init(mode: AppViewModel.Mode, simulationModel: SimulationViewModel, trainingModel: SimulationViewModel) {
        self.mode = mode
        self.simulationModel = simulationModel
        self.trainingModel = trainingModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch mode {
                case .simulation:
                    simulationInspector
                case .training:
                    trainingInspector
                }
            }
            .padding(12)
        }
        .controlSize(.small)
    }

    // MARK: - Simulation Inspector

    @ViewBuilder
    private var simulationInspector: some View {
        ConfigPanelView(model: simulationModel)
    }

    // MARK: - Training Inspector

    @ViewBuilder
    private var trainingInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConfigPanelView(model: trainingModel)
            TrainingConfigPanelView(model: trainingModel)
        }
    }

}

#Preview("Simulation") {
    let buffer = UILoggingBootstrap.buffer
    let logStore = UILogStore(buffer: buffer)
    let simModel = SimulationViewModel(logStore: logStore)
    return InspectorView(mode: .simulation, simulationModel: simModel, trainingModel: simModel)
        .frame(width: 300, height: 700)
}

#Preview("Training") {
    let buffer = UILoggingBootstrap.buffer
    let logStore = UILogStore(buffer: buffer)
    let simModel = SimulationViewModel(logStore: logStore)
    return InspectorView(mode: .training, simulationModel: simModel, trainingModel: simModel)
        .frame(width: 300, height: 700)
}
