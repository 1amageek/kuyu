import Foundation

public struct LearningCampaignSeedRunSummary: Codable, Sendable, Equatable {
    public let seed: String
    public let terminalState: String?
    public let accepted: Bool
    public let acceptedCandidateID: String?
    public let acceptedCheckpointURL: String?
    public let incumbentCandidateID: String?
    public let incumbentFitness: Double?
    public let bestCandidateID: String?
    public let bestFitness: Double?
    public let bestVsIncumbentDelta: Double?
    public let bestTaskPassRate: Double?
    public let bestHoldTimeRatio: Double?
    public let bestAltitudeErrorRatio: Double?
    public let bestSafetyViolationRate: Double?
    public let bestRewardAverage: Double?
    public let gateNearestCandidateID: String?
    public let gateNearestFitness: Double?
    public let gateNearestTaskPassRate: Double?
    public let gateNearestHoldTimeRatio: Double?
    public let gateNearestAltitudeErrorRatio: Double?
    public let gateNearestSafetyViolationRate: Double?
    public let gateNearestRewardAverage: Double?
    public let fitnessCount: Int
    public let reasonCount: Int
    public let evaluationTraceCount: Int
    public let overlappedEvaluation: Bool

    public init(
        seed: String,
        terminalState: String?,
        accepted: Bool,
        acceptedCandidateID: String?,
        acceptedCheckpointURL: String?,
        incumbentCandidateID: String?,
        incumbentFitness: Double?,
        bestCandidateID: String?,
        bestFitness: Double?,
        bestVsIncumbentDelta: Double?,
        bestTaskPassRate: Double?,
        bestHoldTimeRatio: Double?,
        bestAltitudeErrorRatio: Double?,
        bestSafetyViolationRate: Double?,
        bestRewardAverage: Double?,
        gateNearestCandidateID: String?,
        gateNearestFitness: Double?,
        gateNearestTaskPassRate: Double?,
        gateNearestHoldTimeRatio: Double?,
        gateNearestAltitudeErrorRatio: Double?,
        gateNearestSafetyViolationRate: Double?,
        gateNearestRewardAverage: Double?,
        fitnessCount: Int,
        reasonCount: Int,
        evaluationTraceCount: Int,
        overlappedEvaluation: Bool
    ) {
        self.seed = seed
        self.terminalState = terminalState
        self.accepted = accepted
        self.acceptedCandidateID = acceptedCandidateID
        self.acceptedCheckpointURL = acceptedCheckpointURL
        self.incumbentCandidateID = incumbentCandidateID
        self.incumbentFitness = incumbentFitness
        self.bestCandidateID = bestCandidateID
        self.bestFitness = bestFitness
        self.bestVsIncumbentDelta = bestVsIncumbentDelta
        self.bestTaskPassRate = bestTaskPassRate
        self.bestHoldTimeRatio = bestHoldTimeRatio
        self.bestAltitudeErrorRatio = bestAltitudeErrorRatio
        self.bestSafetyViolationRate = bestSafetyViolationRate
        self.bestRewardAverage = bestRewardAverage
        self.gateNearestCandidateID = gateNearestCandidateID
        self.gateNearestFitness = gateNearestFitness
        self.gateNearestTaskPassRate = gateNearestTaskPassRate
        self.gateNearestHoldTimeRatio = gateNearestHoldTimeRatio
        self.gateNearestAltitudeErrorRatio = gateNearestAltitudeErrorRatio
        self.gateNearestSafetyViolationRate = gateNearestSafetyViolationRate
        self.gateNearestRewardAverage = gateNearestRewardAverage
        self.fitnessCount = fitnessCount
        self.reasonCount = reasonCount
        self.evaluationTraceCount = evaluationTraceCount
        self.overlappedEvaluation = overlappedEvaluation
    }
}
