import Foundation

public struct LearningCampaignPlan: Codable, Sendable, Equatable {
    public let artifactRoot: String
    public let task: String
    public let suites: [String]
    public let episodes: Int
    public let workers: Int
    public let population: Int
    public let generations: Int
    public let eliteCount: Int
    public let candidateEvaluationConcurrency: Int
    public let seeds: [String]
    public let sourceCheckpoint: String?
    public let modelDescriptor: String?
    public let variation: String
    public let searchStrategy: String
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let bootstrapSuite: String
    public let bootstrapEpisodes: Int
    public let bootstrapSequence: Int
    public let bootstrapEpochs: Int
    public let bootstrapMaxBatches: Int
    public let bootstrapLearningRate: Double
    public let resumeEnabled: Bool?
    public let resourceSampleSeconds: Double?
    public let availableDiskBytes: Int64
    public let requiredDiskBytes: Int64
    public let plannedCandidateEvaluations: Int
    public let plannedRegressionRollouts: Int
    public let plannedRegressionEpisodes: Int
}
