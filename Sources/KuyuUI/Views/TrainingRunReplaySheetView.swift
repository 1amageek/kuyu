import KuyuTraining
import Logging
import SwiftUI

struct TrainingRunReplaySheetView: View {
    let artifact: TrainingRunInspectionArtifact
    let scenarioIdentity: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            HStack {
                Text("Failure Replay")
                    .font(.headline)
                Spacer(minLength: 0)
                Button {
                    logClose()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close Replay")
            }

            TrainingRunInspectionView(
                artifact: artifact,
                initialScenarioIdentity: scenarioIdentity
            )
        }
        .padding(KuyuSpacing.md)
        .frame(minWidth: 1_100, idealWidth: 1_280, minHeight: 760, idealHeight: 820)
    }

    private func logClose() {
        Logger(label: "kuyu.ui").info("Training failure replay closed", metadata: [
            "action": "closeTrainingFailureReplay",
            "task": .string(artifact.profile.task),
            "scenarioIdentity": .string(scenarioIdentity ?? "default"),
        ])
    }
}
