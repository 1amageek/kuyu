import KuyuScenarios
import SwiftUI

struct EnvironmentConfigView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    Picker("Environment Type", selection: $model.taskMode) {
                        ForEach(SimulationTaskMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    TextField("Suites", text: $model.learningCampaignSuites)
                    IntegerStepperView(label: "Episodes", value: $model.learningCampaignEpisodes, range: 1...10_000)
                    IntegerStepperView(label: "Workers", value: $model.learningCampaignWorkers, range: 1...64)
                    IntegerStepperView(
                        label: "Candidate Evaluation Concurrency",
                        value: $model.learningCampaignCandidateEvaluationConcurrency,
                        range: 1...64
                    )
                    Toggle("Use Environment Config", isOn: $model.useEnvironmentConfig)
                }
                .textFieldStyle(.roundedBorder)
            } label: {
                Label("Environment", systemImage: "cube.transparent")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    StatRow(label: "Observation Space", value: "8ch lift contract")
                    StatRow(label: "Action Space", value: "DriveIntent")
                    StatRow(label: "Reward Definition", value: "task profile")
                    StatRow(label: "Simulation Backend", value: "Kuyu deterministic world")
                    StatRow(label: "Reset Condition", value: "scenario definition")
                }
            } label: {
                Label("Contract", systemImage: "doc.text")
            }
        }
    }
}
