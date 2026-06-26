import Foundation
import KuyuMLX

typealias PostRegressionGateState = ReferenceQuadrotorRegressionInspectionState

struct RegressionRunStore: Sendable {
    private let loader: ReferenceQuadrotorRegressionArtifactLoader

    init(loader: ReferenceQuadrotorRegressionArtifactLoader = ReferenceQuadrotorRegressionArtifactLoader()) {
        self.loader = loader
    }

    func load(from artifactDirectory: URL) throws -> PostRegressionGateState {
        try loader.loadInspectionState(from: artifactDirectory)
    }
}
