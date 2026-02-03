import Foundation
import KuyuMLX

@MainActor
struct TrainingService {
    let modelStore: ManasMLXModelStore

    init(modelStore: ManasMLXModelStore) {
        self.modelStore = modelStore
    }

    func trainCore(request: TrainingRequest) async throws -> TrainingResult {
        try modelStore.trainCore(
            datasetURL: request.datasetURL,
            sequenceLength: request.sequenceLength,
            learningRate: request.learningRate,
            epochs: request.epochs,
            useAux: request.useAux,
            useQualityGating: request.useQualityGating
        )
    }
}
