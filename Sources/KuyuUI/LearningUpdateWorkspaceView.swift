import Foundation
import KuyuTrainingApplication
import SwiftUI

public struct LearningUpdateWorkspaceView: View {
  @State private var model: LearningUpdateViewModel

  public init(runner: any LearningUpdateRunning) {
    self._model = State(
      initialValue: LearningUpdateViewModel(runner: runner)
    )
  }

  public var body: some View {
    Form {
      Section("Training input") {
        TextField("Run ID", text: $model.runID)
        TextField("Dataset directory", text: $model.datasetPath)
        TextField("Source bundle ID", text: $model.sourceBundleID)
        TextField("Source bundle directory", text: $model.sourceBundlePath)
      }
      Section("Candidate output") {
        TextField("Candidate bundle ID", text: $model.candidateBundleID)
        TextField(
          "Candidate bundle directory",
          text: $model.candidateBundlePath
        )
      }
      Section("Execution") {
        statusView
        HStack {
          Button("Train") {
            model.start()
          }
          .disabled(model.state == .running)
          Button("Cancel") {
            model.cancel()
          }
          .disabled(model.state != .running)
        }
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 720, minHeight: 520)
    .navigationTitle("Kuyu Mojo Training")
  }

  @ViewBuilder
  private var statusView: some View {
    switch model.state {
    case .idle:
      Text("Ready")
    case .running:
      ProgressView("Training")
    case .completed(
      let candidateBundleID,
      let transitionCount,
      let metrics
    ):
      LabeledContent("Candidate", value: candidateBundleID)
      LabeledContent("Transitions", value: String(transitionCount))
      LabeledContent("Updates", value: String(metrics.updateCount))
      LabeledContent(
        "Gradient norm",
        value: String(format: "%.6f", metrics.gradientNorm)
      )
    case .cancelled:
      Text("Cancelled")
    case .failed(let reason):
      Text(reason)
        .foregroundStyle(.red)
        .textSelection(.enabled)
    }
  }
}
