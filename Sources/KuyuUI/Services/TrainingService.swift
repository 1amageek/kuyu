import Foundation
import KuyuMLX
import KuyuTraining

@MainActor
public struct TrainingService {
    let runtime: ManasMLXTrainingRuntime

    public init(modelStore: ManasMLXModelStore) {
        self.runtime = ManasMLXTrainingRuntime(modelStore: modelStore)
    }

    public init(runtime: ManasMLXTrainingRuntime) {
        self.runtime = runtime
    }

    public func trainCore(request: TrainingRequest) async throws -> TrainingResult {
        try await runtime.trainSupervised(request: TrainingBackendRequest(
            datasetURL: request.datasetURL,
            sequenceLength: request.sequenceLength,
            epochs: request.epochs,
            learningRate: request.learningRate,
            useAux: request.useAux,
            useQualityGating: request.useQualityGating,
            maxBatches: request.maxBatches
        ))
    }
}
