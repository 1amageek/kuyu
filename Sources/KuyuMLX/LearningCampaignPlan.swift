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
    public let adaptiveMutation: LearningCampaignAdaptiveMutationPlan
    public let bootstrapSuite: String
    public let bootstrapEpisodes: Int
    public let bootstrapSequence: Int
    public let bootstrapEpochs: Int
    public let bootstrapMaxBatches: Int
    public let bootstrapLearningRate: Double
    public let bootstrapRepairAttempts: Int?
    public let verifyParentTask: Bool?
    public let resumeEnabled: Bool?
    public let resourceSampleSeconds: Double?
    public let artifactRetentionPolicy: LearningCampaignArtifactRetentionPolicy
    public let availableDiskBytes: Int64
    public let requiredDiskBytes: Int64
    public let plannedCandidateEvaluations: Int
    public let plannedRegressionRollouts: Int
    public let plannedRegressionEpisodes: Int

    public init(
        artifactRoot: String,
        task: String,
        suites: [String],
        episodes: Int,
        workers: Int,
        population: Int,
        generations: Int,
        eliteCount: Int,
        candidateEvaluationConcurrency: Int,
        seeds: [String],
        sourceCheckpoint: String?,
        modelDescriptor: String?,
        variation: String,
        searchStrategy: String,
        mutationRate: Double,
        mutationNoiseScale: Double,
        adaptiveMutation: LearningCampaignAdaptiveMutationPlan = LearningCampaignAdaptiveMutationPlan(),
        bootstrapSuite: String,
        bootstrapEpisodes: Int,
        bootstrapSequence: Int,
        bootstrapEpochs: Int,
        bootstrapMaxBatches: Int,
        bootstrapLearningRate: Double,
        bootstrapRepairAttempts: Int?,
        verifyParentTask: Bool?,
        resumeEnabled: Bool?,
        resourceSampleSeconds: Double?,
        artifactRetentionPolicy: LearningCampaignArtifactRetentionPolicy = .full,
        availableDiskBytes: Int64,
        requiredDiskBytes: Int64,
        plannedCandidateEvaluations: Int,
        plannedRegressionRollouts: Int,
        plannedRegressionEpisodes: Int
    ) {
        self.artifactRoot = artifactRoot
        self.task = task
        self.suites = suites
        self.episodes = episodes
        self.workers = workers
        self.population = population
        self.generations = generations
        self.eliteCount = eliteCount
        self.candidateEvaluationConcurrency = candidateEvaluationConcurrency
        self.seeds = seeds
        self.sourceCheckpoint = sourceCheckpoint
        self.modelDescriptor = modelDescriptor
        self.variation = variation
        self.searchStrategy = searchStrategy
        self.mutationRate = mutationRate
        self.mutationNoiseScale = mutationNoiseScale
        self.adaptiveMutation = adaptiveMutation
        self.bootstrapSuite = bootstrapSuite
        self.bootstrapEpisodes = bootstrapEpisodes
        self.bootstrapSequence = bootstrapSequence
        self.bootstrapEpochs = bootstrapEpochs
        self.bootstrapMaxBatches = bootstrapMaxBatches
        self.bootstrapLearningRate = bootstrapLearningRate
        self.bootstrapRepairAttempts = bootstrapRepairAttempts
        self.verifyParentTask = verifyParentTask
        self.resumeEnabled = resumeEnabled
        self.resourceSampleSeconds = resourceSampleSeconds
        self.artifactRetentionPolicy = artifactRetentionPolicy
        self.availableDiskBytes = availableDiskBytes
        self.requiredDiskBytes = requiredDiskBytes
        self.plannedCandidateEvaluations = plannedCandidateEvaluations
        self.plannedRegressionRollouts = plannedRegressionRollouts
        self.plannedRegressionEpisodes = plannedRegressionEpisodes
    }
}
