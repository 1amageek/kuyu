import Foundation
import KuyuCore
import KuyuPhysics
import KuyuTraining

public enum LearningCampaignTask: String, CaseIterable, Codable, Sendable, Equatable {
    case lift
    case singleLift

    public var rolloutTask: LearningCampaignRolloutTask {
        switch self {
        case .lift:
            return .lift
        case .singleLift:
            return .singleLift
        }
    }
}

public enum LearningCampaignRolloutTask: String, CaseIterable, Codable, Sendable, Equatable {
    case attitude
    case lift
    case singleLift
}

public enum LearningCampaignTier: String, CaseIterable, Codable, Sendable, Equatable {
    case tier0
    case tier1
    case tier2

    public func makeDeterminism() throws -> DeterminismConfig {
        switch self {
        case .tier0:
            return try DeterminismConfig(tier: .tier0)
        case .tier1:
            return try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
        case .tier2:
            return try DeterminismConfig(tier: .tier2)
        }
    }
}

public enum LearningCampaignVariation: String, CaseIterable, Codable, Sendable, Equatable {
    case copy
    case gaussian
}

public enum LearningCampaignRunPreset: String, CaseIterable, Codable, Sendable, Equatable {
    case smoke
    case standard
    case fiveGeneration
    case full

    public func apply(to config: LearningCampaignRunConfig) -> LearningCampaignRunConfig {
        var updated = config
        switch self {
        case .smoke:
            updated.suites = [6]
            updated.seedCount = 1
            updated.population = 2
            updated.generations = 1
            updated.workers = 1
            updated.candidateEvaluationConcurrency = 1
            updated.episodes = 1
            updated.artifactRetention = .compact
        case .standard:
            updated.suites = [6]
            updated.seedCount = 1
            updated.population = 4
            updated.generations = 1
            updated.workers = 1
            updated.candidateEvaluationConcurrency = 1
            updated.episodes = 1
            updated.artifactRetention = .full
        case .fiveGeneration:
            updated.suites = [6]
            updated.seedCount = 1
            updated.population = 8
            updated.generations = 5
            updated.eliteCount = 2
            updated.workers = 1
            updated.candidateEvaluationConcurrency = 1
            updated.episodes = 1
            updated.adaptiveMutationEnabled = true
            updated.minimumIncumbentImprovement = 0
            updated.artifactRetention = .full
        case .full:
            updated.suites = [6, 7, 8]
            updated.seedCount = 3
            updated.population = 4
            updated.generations = 2
            updated.workers = 2
            updated.candidateEvaluationConcurrency = 2
            updated.episodes = 1
            updated.adaptiveMutationEnabled = true
            updated.minimumIncumbentImprovement = 0.01
            updated.artifactRetention = .compact
        }
        return updated
    }
}

public struct LearningCampaignRunConfig: Sendable, Codable, Equatable {
    public var task: LearningCampaignTask
    public var sourceCheckpoint: URL
    public var artifactRoot: URL
    public var explicitSeeds: [String]?
    public var seedCount: Int
    public var population: Int
    public var generations: Int
    public var eliteCount: Int
    public var workers: Int
    public var candidateEvaluationConcurrency: Int
    public var suites: [Int]
    public var episodes: Int
    public var tier: LearningCampaignTier
    public var cutPeriodSteps: UInt64
    public var modelDescriptorPath: String
    public var mutationRate: Double
    public var mutationNoiseScale: Double
    public var adaptiveMutationEnabled: Bool
    public var mutationIncreaseFactor: Double
    public var mutationDecayFactor: Double
    public var minimumMutationRate: Double
    public var maximumMutationRate: Double
    public var minimumMutationNoiseScale: Double
    public var maximumMutationNoiseScale: Double
    public var searchStrategy: EvolutionSearchStrategy
    public var variation: LearningCampaignVariation
    public var minimumRewardAverage: Double?
    public var minimumIncumbentImprovement: Double
    public var minimumNoveltyScore: Double?
    public var resourceSampleSeconds: Double
    public var artifactRetention: LearningCampaignArtifactRetentionMode
    public var kp: Double
    public var kd: Double
    public var yawDamping: Double
    public var hoverScale: Double
    public var qualityGateEnabled: Bool
    public var allowsNonEmptyArtifactRoot: Bool
    public var requiresInitialParentPass: Bool
    public var autonomyDomain: AutonomousOperationDomain
    public var autonomousPipelinePlan: AutonomousTrainingPipelinePlan?
    public var reinforcementTrainingArtifactDirectory: URL?

    public init(
        task: LearningCampaignTask = .lift,
        sourceCheckpoint: URL,
        artifactRoot: URL,
        explicitSeeds: [String]? = nil,
        seedCount: Int = 1,
        population: Int = 4,
        generations: Int = 1,
        eliteCount: Int = 1,
        workers: Int = 1,
        candidateEvaluationConcurrency: Int = 1,
        suites: [Int] = [6],
        episodes: Int = 1,
        tier: LearningCampaignTier = .tier1,
        cutPeriodSteps: UInt64 = 2,
        modelDescriptorPath: String = "",
        mutationRate: Double = 0.08,
        mutationNoiseScale: Double = 0.01,
        adaptiveMutationEnabled: Bool = false,
        mutationIncreaseFactor: Double = 1.25,
        mutationDecayFactor: Double = 0.9,
        minimumMutationRate: Double = 0,
        maximumMutationRate: Double = 0.5,
        minimumMutationNoiseScale: Double = 0,
        maximumMutationNoiseScale: Double = 0.1,
        searchStrategy: EvolutionSearchStrategy = .qualityDiversity,
        variation: LearningCampaignVariation = .gaussian,
        minimumRewardAverage: Double? = nil,
        minimumIncumbentImprovement: Double = 0,
        minimumNoveltyScore: Double? = nil,
        resourceSampleSeconds: Double = 30,
        artifactRetention: LearningCampaignArtifactRetentionMode = .full,
        kp: Double = 0.35,
        kd: Double = 0.08,
        yawDamping: Double = 0.04,
        hoverScale: Double = 1.0,
        qualityGateEnabled: Bool = true,
        allowsNonEmptyArtifactRoot: Bool = false,
        requiresInitialParentPass: Bool = true,
        autonomyDomain: AutonomousOperationDomain = .aerialDrone,
        autonomousPipelinePlan: AutonomousTrainingPipelinePlan? = nil,
        reinforcementTrainingArtifactDirectory: URL? = nil
    ) {
        self.task = task
        self.sourceCheckpoint = sourceCheckpoint
        self.artifactRoot = artifactRoot
        self.explicitSeeds = explicitSeeds
        self.seedCount = seedCount
        self.population = population
        self.generations = generations
        self.eliteCount = eliteCount
        self.workers = workers
        self.candidateEvaluationConcurrency = candidateEvaluationConcurrency
        self.suites = suites
        self.episodes = episodes
        self.tier = tier
        self.cutPeriodSteps = cutPeriodSteps
        self.modelDescriptorPath = modelDescriptorPath
        self.mutationRate = mutationRate
        self.mutationNoiseScale = mutationNoiseScale
        self.adaptiveMutationEnabled = adaptiveMutationEnabled
        self.mutationIncreaseFactor = mutationIncreaseFactor
        self.mutationDecayFactor = mutationDecayFactor
        self.minimumMutationRate = minimumMutationRate
        self.maximumMutationRate = maximumMutationRate
        self.minimumMutationNoiseScale = minimumMutationNoiseScale
        self.maximumMutationNoiseScale = maximumMutationNoiseScale
        self.searchStrategy = searchStrategy
        self.variation = variation
        self.minimumRewardAverage = minimumRewardAverage
        self.minimumIncumbentImprovement = minimumIncumbentImprovement
        self.minimumNoveltyScore = minimumNoveltyScore
        self.resourceSampleSeconds = resourceSampleSeconds
        self.artifactRetention = artifactRetention
        self.kp = kp
        self.kd = kd
        self.yawDamping = yawDamping
        self.hoverScale = hoverScale
        self.qualityGateEnabled = qualityGateEnabled
        self.allowsNonEmptyArtifactRoot = allowsNonEmptyArtifactRoot
        self.requiresInitialParentPass = requiresInitialParentPass
        self.autonomyDomain = autonomyDomain
        self.autonomousPipelinePlan = autonomousPipelinePlan
        self.reinforcementTrainingArtifactDirectory = reinforcementTrainingArtifactDirectory
    }
}

public enum LearningCampaignRunEvent: Sendable, Equatable {
    case preflightStarted
    case preflightCompleted
    case parentEvaluationStarted(label: String, checkpointPath: String)
    case parentEvaluationCompleted(label: String, checkpointPath: String)
    case checkpointRegressionStarted(label: String, checkpointPath: String)
    case checkpointRegressionCompleted(label: String, accepted: Bool, reasons: [String])
    case seedStarted(seed: String)
    case generationStarted(seed: String, generationIndex: Int)
    case candidateEvaluated(seed: String, generationIndex: Int, candidateID: String, fitness: Double)
    case generationCompleted(seed: String, generationIndex: Int, bestCandidateID: String?)
    case seedCompleted(seed: String, accepted: Bool, bestCandidateID: String?)
    case artifactWritten(name: String, path: String)
    case finished(summary: LearningCampaignSummary)
    case failed(reason: String)
    case cancelled
}

@MainActor
public final class LearningCampaignRunHandle {
    public let progress: Progress
    public let events: AsyncStream<LearningCampaignRunEvent>
    private let continuation: AsyncStream<LearningCampaignRunEvent>.Continuation
    private var task: Task<LearningCampaignSummary, Error>?
    private var completedResult: Result<LearningCampaignSummary, Error>?

    init(progress: Progress) {
        self.progress = progress
        var localContinuation: AsyncStream<LearningCampaignRunEvent>.Continuation?
        self.events = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation!
    }

    func start(_ operation: @escaping @Sendable () async throws -> LearningCampaignSummary) {
        completedResult = nil
        let continuation = self.continuation
        task = Task {
            do {
                let summary = try await operation()
                continuation.finish()
                Task { @MainActor in
                    completedResult = .success(summary)
                    task = nil
                }
                return summary
            } catch {
                continuation.finish()
                Task { @MainActor in
                    completedResult = .failure(error)
                    task = nil
                }
                throw error
            }
        }
        progress.isCancellable = true
        progress.cancellationHandler = { [weak self] in
            Task { @MainActor in
                self?.cancel()
            }
        }
    }

    public func emit(_ event: LearningCampaignRunEvent) {
        continuation.yield(event)
    }

    public func cancel() {
        if !progress.isCancelled {
            progress.cancel()
        }
        task?.cancel()
    }

    public func wait() async throws -> LearningCampaignSummary {
        if let task {
            return try await task.value
        }
        if let completedResult {
            return try completedResult.get()
        }
        throw CancellationError()
    }
}
