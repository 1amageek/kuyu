import Foundation
import KuyuMLX

struct TrainingBootstrapInput: Sendable, Equatable {
    let datasetURL: URL
    let sequenceLength: Int
    let epochs: Int
    let learningRate: Double
    let useAux: Bool
    let useQualityGating: Bool
}

struct TrainingBootstrapCoordinator {
    func makeRequest(input: TrainingBootstrapInput) -> TrainingRequest {
        TrainingRequest(
            datasetURL: input.datasetURL,
            sequenceLength: input.sequenceLength,
            epochs: input.epochs,
            learningRate: input.learningRate,
            useAux: input.useAux,
            useQualityGating: input.useQualityGating
        )
    }
}
