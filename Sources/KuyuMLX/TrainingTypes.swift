import Foundation

public struct TrainingRequest: Sendable, Equatable {
    public let datasetURL: URL
    public let sequenceLength: Int
    public let epochs: Int
    public let learningRate: Double
    public let useAux: Bool
    public let useQualityGating: Bool

    public init(
        datasetURL: URL,
        sequenceLength: Int,
        epochs: Int,
        learningRate: Double,
        useAux: Bool,
        useQualityGating: Bool
    ) {
        self.datasetURL = datasetURL
        self.sequenceLength = sequenceLength
        self.epochs = epochs
        self.learningRate = learningRate
        self.useAux = useAux
        self.useQualityGating = useQualityGating
    }
}

public struct TrainingResult: Sendable, Equatable {
    public let finalLoss: Double
    public let epochs: Int

    public init(finalLoss: Double, epochs: Int) {
        self.finalLoss = finalLoss
        self.epochs = epochs
    }
}
