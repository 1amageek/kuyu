import KuyuScenarios
import SwiftUI

struct EnvironmentConfigView: View {
    @Bindable var model: SimulationViewModel
    // The environment name lives on AppViewModel and drives the task mode;
    // exposing it here keeps a single control for the environment axis.
    @Binding var environmentName: String

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    Picker("Environment", selection: $environmentName) {
                        Text("QuadLift-v1").tag("QuadLift-v1")
                        Text("SinglePropLift-v1").tag("SinglePropLift-v1")
                        Text("Attitude-v1").tag("Attitude-v1")
                    }
                    StatRow(label: "Task Mode", value: model.taskMode.rawValue)
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
