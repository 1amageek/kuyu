import Foundation
import KuyuTraining

public struct ManasMLXTrainingWorkerOutcome: Sendable, Equatable {
    public let runID: String
    public let artifactRoot: URL
    public let terminalState: TrainingRunTerminalState
    public let generationCount: Int
    public let candidateCount: Int
    public let hasAcceptedCheckpoint: Bool
    public let failureReasons: [String]

    public init(
        runID: String,
        artifactRoot: URL,
        terminalState: TrainingRunTerminalState,
        generationCount: Int,
        candidateCount: Int,
        hasAcceptedCheckpoint: Bool,
        failureReasons: [String]
    ) {
        self.runID = runID
        self.artifactRoot = artifactRoot
        self.terminalState = terminalState
        self.generationCount = generationCount
        self.candidateCount = candidateCount
        self.hasAcceptedCheckpoint = hasAcceptedCheckpoint
        self.failureReasons = failureReasons
    }

    public var processDisposition: TrainingRunWorkerProcessDisposition {
        TrainingRunWorkerProcessDisposition(
            terminalState: terminalState,
            hasAcceptedCheckpoint: hasAcceptedCheckpoint
        )
    }
}
