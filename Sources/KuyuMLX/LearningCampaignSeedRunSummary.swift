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
    public let bestSafetyViolationRate: Double?
    public let bestRewardAverage: Double?
    public let fitnessCount: Int
    public let reasonCount: Int
    public let evaluationTraceCount: Int
    public let overlappedEvaluation: Bool
}
