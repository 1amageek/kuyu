import KuyuScenarios
import SwiftUI

public struct SettingsWorkspaceView: View {
    @Bindable var model: SimulationViewModel

    public init(model: SimulationViewModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                HStack(alignment: .top, spacing: KuyuSpacing.md) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                            Picker("Default Task", selection: $model.taskMode) {
                                ForEach(SimulationTaskMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            Picker("Default Controller", selection: $model.controllerSelection) {
                                ForEach(ControllerSelection.allCases) { controller in
                                    Text(controller.rawValue).tag(controller)
                                }
                            }
                            Toggle("Use Render Assets", isOn: $model.useRenderAssets)
                            Toggle("Use Environment Config", isOn: $model.useEnvironmentConfig)
                        }
                    } label: {
                        Label("General", systemImage: "gearshape")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                            TextField("Log Directory", text: $model.logDirectory)
                            TextField("Training Dataset Directory", text: $model.trainingDatasetDirectory)
                            Picker("Log Level", selection: $model.logLevel) {
                                ForEach(LogLevelOption.allCases) { level in
                                    Text(level.rawValue).tag(level)
                                }
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                    } label: {
                        Label("Storage / Logging", systemImage: "externaldrive")
                    }
                }
            }
            .padding(KuyuSpacing.md)
        }
    }
}
