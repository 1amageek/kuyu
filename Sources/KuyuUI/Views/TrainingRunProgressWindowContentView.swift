import Foundation
import KuyuTraining
import SwiftUI

@MainActor
public struct TrainingRunProgressWindowContentView: View {
    @State private var model: TrainingRunsViewModel
    private let runID: String

    public init(runDirectoryPath: String) {
        let runDirectory = URL(fileURLWithPath: runDirectoryPath, isDirectory: true)
            .standardizedFileURL
        self.runID = runDirectory.lastPathComponent
        self._model = State(initialValue: TrainingRunsViewModel(environment: [
            TrainingRunContractSchema.runRootEnvironmentKey:
                runDirectory.deletingLastPathComponent().path,
        ]))
    }

    public var body: some View {
        TrainingRunsWorkspaceView(model: model)
            .frame(minWidth: 1_120, minHeight: 720)
            .task(id: runID) {
                guard model.selectedRunID != runID else { return }
                model.selectedRunID = runID
            }
    }
}
