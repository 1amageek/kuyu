import Foundation

public struct TrainingRequest: Sendable, Equatable {
    public let datasetURL: URL
    public let sequenceLength: Int
    public let epochs: Int
    public let learningRate: Double
    public let useAux: Bool
    public let useQualityGating: Bool
    public let maxBatches: Int?

    public init(
        datasetURL: URL,
        sequenceLength: Int,
        epochs: Int,
        learningRate: Double,
        useAux: Bool,
        useQualityGating: Bool,
        maxBatches: Int? = nil
    ) {
        self.datasetURL = datasetURL
        self.sequenceLength = sequenceLength
        self.epochs = epochs
        self.learningRate = learningRate
        self.useAux = useAux
        self.useQualityGating = useQualityGating
        self.maxBatches = maxBatches
    }
}

public struct TrainingResult: Sendable, Equatable {
    public let finalLoss: Double
    public let epochs: Int
    public let openLoopFit: OpenLoopDriveFit?
    public let reloadedOpenLoopFit: OpenLoopDriveFit?

    public var openLoopDriveMAE: Double? { openLoopFit?.meanAbsoluteError }
    public var openLoopPredictionAverage: Double? { openLoopFit?.predictionAverage }
    public var openLoopTargetAverage: Double? { openLoopFit?.targetAverage }
    public var reloadedOpenLoopDriveMAE: Double? { reloadedOpenLoopFit?.meanAbsoluteError }
    public var reloadedOpenLoopPredictionAverage: Double? { reloadedOpenLoopFit?.predictionAverage }
    public var reloadedOpenLoopTargetAverage: Double? { reloadedOpenLoopFit?.targetAverage }

    public init(
        finalLoss: Double,
        epochs: Int,
        openLoopFit: OpenLoopDriveFit? = nil,
        reloadedOpenLoopFit: OpenLoopDriveFit? = nil
    ) {
        self.finalLoss = finalLoss
        self.epochs = epochs
        self.openLoopFit = openLoopFit
        self.reloadedOpenLoopFit = reloadedOpenLoopFit
    }
}

public struct OpenLoopDriveFit: Sendable, Equatable {
    public let meanAbsoluteError: Double
    public let predictionAverage: Double
    public let targetAverage: Double
    public let firstPrediction: Double?
    public let firstTarget: Double?

    public init(
        meanAbsoluteError: Double,
        predictionAverage: Double,
        targetAverage: Double,
        firstPrediction: Double? = nil,
        firstTarget: Double? = nil
    ) {
        self.meanAbsoluteError = meanAbsoluteError
        self.predictionAverage = predictionAverage
        self.targetAverage = targetAverage
        self.firstPrediction = firstPrediction
        self.firstTarget = firstTarget
    }
}
