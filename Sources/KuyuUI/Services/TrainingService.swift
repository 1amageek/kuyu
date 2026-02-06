import Foundation
import KuyuMLX

@MainActor
public struct TrainingService {
    let modelStore: ManasMLXModelStore

    public init(modelStore: ManasMLXModelStore) {
        self.modelStore = modelStore
    }

    public func trainCore(request: TrainingRequest) async throws -> TrainingResult {
        try await modelStore.trainCore(
            datasetURL: request.datasetURL,
            sequenceLength: request.sequenceLength,
            learningRate: request.learningRate,
            epochs: request.epochs,
            useAux: request.useAux,
            useQualityGating: request.useQualityGating
        )
    }
}
