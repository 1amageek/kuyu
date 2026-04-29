import Foundation

struct TrainingLiveStatus: Sendable, Equatable {
    enum Phase: String, Sendable, Codable, Equatable, CaseIterable {
        case idle
        case preparing
        case rollout
        case datasetExport
        case supervisedTraining
        case reinforcementTraining
        case evaluating
        case completed
        case failed
        case paused
        case stopped
    }

    var phase: Phase
    var message: String
    var iteration: Int
    var datasetPath: String?
    var datasetCount: Int?
    var epochs: Int?
    var learningRate: Double?
    var passRate: Double?
    var failureRate: Double?
    var safetyViolationSeconds: Double?
    var lastRunPassed: Bool?
    var convergenceAccepted: Bool?
    var convergenceReason: String?
    var plateauDetected: Bool?
    var overfitRiskDetected: Bool?
    var safetyRegressionDetected: Bool?
    var checkpointState: String?
    var checkpointReason: String?
    var bestCheckpointID: String?
    var artifactDirectoryPath: String?
    var updatedAt: Date

    init(
        phase: Phase,
        message: String,
        iteration: Int = 0,
        datasetPath: String? = nil,
        datasetCount: Int? = nil,
        epochs: Int? = nil,
        learningRate: Double? = nil,
        passRate: Double? = nil,
        failureRate: Double? = nil,
        safetyViolationSeconds: Double? = nil,
        lastRunPassed: Bool? = nil,
        convergenceAccepted: Bool? = nil,
        convergenceReason: String? = nil,
        plateauDetected: Bool? = nil,
        overfitRiskDetected: Bool? = nil,
        safetyRegressionDetected: Bool? = nil,
        checkpointState: String? = nil,
        checkpointReason: String? = nil,
        bestCheckpointID: String? = nil,
        artifactDirectoryPath: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.phase = phase
        self.message = message
        self.iteration = iteration
        self.datasetPath = datasetPath
        self.datasetCount = datasetCount
        self.epochs = epochs
        self.learningRate = learningRate
        self.passRate = passRate
        self.failureRate = failureRate
        self.safetyViolationSeconds = safetyViolationSeconds
        self.lastRunPassed = lastRunPassed
        self.convergenceAccepted = convergenceAccepted
        self.convergenceReason = convergenceReason
        self.plateauDetected = plateauDetected
        self.overfitRiskDetected = overfitRiskDetected
        self.safetyRegressionDetected = safetyRegressionDetected
        self.checkpointState = checkpointState
        self.checkpointReason = checkpointReason
        self.bestCheckpointID = bestCheckpointID
        self.artifactDirectoryPath = artifactDirectoryPath
        self.updatedAt = updatedAt
    }

    static var idle: TrainingLiveStatus {
        TrainingLiveStatus(phase: .idle, message: "Idle")
    }
}

