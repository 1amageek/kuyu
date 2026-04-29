import Foundation
import KuyuTraining

@MainActor
public struct ManasMLXTrainingRuntime {
    private let modelStore: ManasMLXModelStore
    private let preflight: MLXRuntimePreflight

    public init(
        modelStore: ManasMLXModelStore,
        preflight: MLXRuntimePreflight = MLXRuntimePreflight()
    ) {
        self.modelStore = modelStore
        self.preflight = preflight
    }

    public func trainSupervised(request: TrainingBackendRequest) async throws -> TrainingResult {
        try preflight.check()
        if let sourceSnapshot = request.sourceSnapshot,
           let checkpointURL = sourceSnapshot.checkpointURL {
            try modelStore.loadModel(from: checkpointURL)
        }
        return try await modelStore.trainCore(
            datasetURL: request.datasetURL,
            sequenceLength: request.sequenceLength,
            learningRate: request.learningRate,
            epochs: request.epochs,
            useAux: request.useAux,
            useQualityGating: request.useQualityGating,
            maxBatches: request.maxBatches
        )
    }

    public func saveCandidateCheckpoint(to directory: URL) throws -> ManasMLXModelManifest {
        try modelStore.saveModel(to: directory)
    }
}
