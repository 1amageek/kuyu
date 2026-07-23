import KuyuTraining
import SwiftUI

public struct TrainingInspectionArtifactWindowContentView: View {
    private enum LoadState {
        case loaded(TrainingRunInspectionArtifact)
        case invalid(String)
    }

    private let state: LoadState

    public init(path: String) {
        do {
            state = .loaded(
                try TrainingRunInspectionArtifactStore().validatedArtifact(
                    at: URL(fileURLWithPath: path, isDirectory: false)
                )
            )
        } catch {
            state = .invalid(String(describing: error))
        }
    }

    @ViewBuilder
    public var body: some View {
        switch state {
        case .loaded(let artifact):
            TrainingRunInspectionView(artifact: artifact)
                .padding(KuyuSpacing.md)
        case .invalid(let reason):
            ContentUnavailableView(
                "Inspection Artifact Invalid",
                systemImage: "exclamationmark.triangle",
                description: Text(reason)
            )
        }
    }
}
