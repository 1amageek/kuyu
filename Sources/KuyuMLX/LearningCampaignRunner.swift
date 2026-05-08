import Foundation
import KuyuCore
import KuyuPhysics
import KuyuTraining

public enum LearningCampaignRunError: Error, Sendable, Equatable, LocalizedError {
    case invalidConfig(String)
    case invalidSeed(String)
    case duplicateSeed(String)
    case artifactRootNotEmpty(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfig(let message):
            return message
        case .invalidSeed(let seed):
            return "Invalid campaign seed: \(seed)"
        case .duplicateSeed(let seed):
            return "Duplicate campaign seed: \(seed)"
        case .artifactRootNotEmpty(let path):
            return "Artifact root is not empty: \(path)"
        }
    }
}

@MainActor
public final class LearningCampaignRunner {
    public init() {}

    public func start(config: LearningCampaignRunConfig) throws -> LearningCampaignRunHandle {
        let totalUnitCount = progressTotalUnitCount(config: config)
        let progress = Progress(totalUnitCount: totalUnitCount)
        progress.kind = .file
        progress.localizedDescription = "Preparing learning campaign"
        let handle = LearningCampaignRunHandle(progress: progress)
        let context = LearningCampaignRunContext(handle: handle)
        handle.start { [self] in
            do {
                context.emit(.preflightStarted)
                try context.checkCancellation()
                let orchestratorConfig = try makeOrchestratorConfig(config: config)
                try preflight(config: config)
                context.emit(.preflightCompleted)
                context.advanceProgress(description: "Preflight completed")
                let orchestrator = try makeOrchestrator(config: config)
                return try await orchestrator.run(config: orchestratorConfig, context: context)
            } catch is CancellationError {
                context.emit(.cancelled)
                throw CancellationError()
            } catch {
                context.emit(.failed(reason: String(describing: error)))
                throw error
            }
        }
        return handle
    }

    public func makeOrchestratorConfig(
        config: LearningCampaignRunConfig
    ) throws -> LearningCampaignOrchestratorConfig {
        try validate(config: config)
        let artifactRoot = config.artifactRoot
        try rejectNonEmptyArtifactRootIfNeeded(config)
        let seeds = try resolveSeeds(explicitSeeds: config.explicitSeeds, seedCount: config.seedCount)
        let suites = try validateSuites(config.suites)
        let profile = try TaskEvaluationProfile.profile(task: config.task.rawValue)
        let availableDiskBytes = try availableDiskBytes(at: artifactRoot)
        let adaptiveMutationPlan = LearningCampaignAdaptiveMutationPlan(
            enabled: config.adaptiveMutationEnabled,
            increaseFactor: config.mutationIncreaseFactor,
            decayFactor: config.mutationDecayFactor,
            minimumMutationRate: config.minimumMutationRate,
            maximumMutationRate: config.maximumMutationRate,
            minimumNoiseScale: config.minimumMutationNoiseScale,
            maximumNoiseScale: config.maximumMutationNoiseScale
        )
        let plan = LearningCampaignPlan(
            artifactRoot: artifactRoot.path,
            task: profile.task,
            suites: suites.map(String.init),
            episodes: config.episodes,
            workers: config.workers,
            population: config.population,
            generations: config.generations,
            eliteCount: config.eliteCount,
            candidateEvaluationConcurrency: config.candidateEvaluationConcurrency,
            seeds: seeds,
            sourceCheckpoint: config.sourceCheckpoint.path,
            modelDescriptor: config.modelDescriptorPath.isEmpty ? nil : config.modelDescriptorPath,
            variation: config.variation.rawValue,
            searchStrategy: config.searchStrategy.rawValue,
            mutationRate: config.mutationRate,
            mutationNoiseScale: config.mutationNoiseScale,
            adaptiveMutation: adaptiveMutationPlan,
            bootstrapSuite: suites.first.map(String.init) ?? "6",
            bootstrapEpisodes: 0,
            bootstrapSequence: 0,
            bootstrapEpochs: 0,
            bootstrapMaxBatches: 0,
            bootstrapLearningRate: 0,
            bootstrapRepairAttempts: 0,
            verifyParentTask: true,
            resumeEnabled: false,
            resourceSampleSeconds: config.resourceSampleSeconds,
            artifactRetentionPolicy: retentionPolicy(config.artifactRetention),
            availableDiskBytes: availableDiskBytes,
            requiredDiskBytes: 1,
            plannedCandidateEvaluations: seeds.count * config.population * config.generations,
            plannedRegressionRollouts: seeds.count * config.population * config.generations * suites.count,
            plannedRegressionEpisodes: seeds.count * config.population * config.generations * suites.count * config.episodes
        )
        return LearningCampaignOrchestratorConfig(
            plan: plan,
            artifactRoot: artifactRoot,
            initialParentCheckpointURL: config.sourceCheckpoint,
            allowsNonEmptyArtifactRoot: config.allowsNonEmptyArtifactRoot
        )
    }

    public func preflight(config: LearningCampaignRunConfig) throws {
        _ = try ManasMLXE2EPreflight().check(
            descriptorPath: config.modelDescriptorPath,
            sourceCheckpointURL: config.sourceCheckpoint,
            requireSourceCheckpoint: true
        )
    }

    public func makeOrchestrator(config: LearningCampaignRunConfig) throws -> LearningCampaignOrchestrator {
        let determinism = try config.tier.makeDeterminism()
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: config.cutPeriodSteps)
        let gains = try ImuRateDampingCutGains(
            kp: config.kp,
            kd: config.kd,
            yawDamping: config.yawDamping,
            hoverThrustScale: config.hoverScale
        )
        let checkpointEvaluator = ManasMLXCheckpointEvaluator(config: ManasMLXCheckpointEvaluatorConfig(
            descriptorPath: config.modelDescriptorPath,
            determinism: determinism,
            schedule: schedule,
            gains: gains,
            useQualityGating: config.qualityGateEnabled
        ))
        let profile = try TaskEvaluationProfile.profile(task: config.task.rawValue)
        let minimumRewardAverage = KuyuRegressionQualityGatePolicy.minimumRewardAverage(
            override: config.minimumRewardAverage,
            task: profile.task
        )
        let evolutionRunner = LearningCampaignEvolutionRunner(
            config: config,
            minimumRewardAverage: minimumRewardAverage
        )
        let checkpointRegressionChecker = LearningCampaignCheckpointRegressionChecker(
            config: config,
            minimumRewardAverage: minimumRewardAverage
        )
        return LearningCampaignOrchestrator(
            checkpointEvaluator: checkpointEvaluator,
            evolutionRunner: evolutionRunner,
            checkpointRegressionChecker: checkpointRegressionChecker
        )
    }

    public func resolveSeeds(explicitSeeds: [String]?, seedCount: Int) throws -> [String] {
        guard seedCount > 0 else {
            throw LearningCampaignRunError.invalidConfig("seedCount must be greater than 0.")
        }
        guard let explicitSeeds else {
            return (1...seedCount).map(String.init)
        }
        if seedCount != 1 {
            throw LearningCampaignRunError.invalidConfig("explicitSeeds and seedCount cannot both be used.")
        }
        guard !explicitSeeds.isEmpty else {
            throw LearningCampaignRunError.invalidConfig("explicitSeeds must not be empty.")
        }
        var seenSeeds = Set<String>()
        var values: [String] = []
        for rawSeed in explicitSeeds {
            let trimmed = rawSeed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let seed = UInt64(trimmed) else {
                throw LearningCampaignRunError.invalidSeed(rawSeed)
            }
            let value = String(seed)
            guard seenSeeds.insert(value).inserted else {
                throw LearningCampaignRunError.duplicateSeed(value)
            }
            values.append(value)
        }
        return values
    }

    public func validateSuites(_ suites: [Int]) throws -> [Int] {
        guard !suites.isEmpty else {
            throw LearningCampaignRunError.invalidConfig("At least one suite is required.")
        }
        let validSuites = Set([6, 7, 8])
        var seenSuites = Set<Int>()
        var values: [Int] = []
        for suite in suites {
            guard validSuites.contains(suite) else {
                throw LearningCampaignRunError.invalidConfig("Unsupported suite: \(suite)")
            }
            guard seenSuites.insert(suite).inserted else {
                throw LearningCampaignRunError.invalidConfig("Duplicate suite: \(suite)")
            }
            values.append(suite)
        }
        return values
    }

    private func validate(config: LearningCampaignRunConfig) throws {
        guard config.population > 0 else {
            throw LearningCampaignRunError.invalidConfig("population must be greater than 0.")
        }
        guard config.generations > 0 else {
            throw LearningCampaignRunError.invalidConfig("generations must be greater than 0.")
        }
        guard config.eliteCount > 0, config.eliteCount <= config.population else {
            throw LearningCampaignRunError.invalidConfig("eliteCount must be between 1 and population.")
        }
        guard config.workers > 0 else {
            throw LearningCampaignRunError.invalidConfig("workers must be greater than 0.")
        }
        guard config.candidateEvaluationConcurrency > 0,
              config.candidateEvaluationConcurrency <= config.population else {
            throw LearningCampaignRunError.invalidConfig("candidateEvaluationConcurrency must be between 1 and population.")
        }
        guard config.episodes > 0 else {
            throw LearningCampaignRunError.invalidConfig("episodes must be greater than 0.")
        }
        guard config.mutationRate.isFinite, config.mutationRate >= 0 else {
            throw LearningCampaignRunError.invalidConfig("mutationRate must be finite and non-negative.")
        }
        guard config.mutationNoiseScale.isFinite, config.mutationNoiseScale >= 0 else {
            throw LearningCampaignRunError.invalidConfig("mutationNoiseScale must be finite and non-negative.")
        }
        guard config.mutationIncreaseFactor.isFinite, config.mutationIncreaseFactor >= 1 else {
            throw LearningCampaignRunError.invalidConfig("mutationIncreaseFactor must be finite and at least 1.")
        }
        guard config.mutationDecayFactor.isFinite,
              config.mutationDecayFactor >= 0,
              config.mutationDecayFactor <= 1 else {
            throw LearningCampaignRunError.invalidConfig("mutationDecayFactor must be finite and between 0 and 1.")
        }
        guard config.minimumMutationRate.isFinite, config.minimumMutationRate >= 0 else {
            throw LearningCampaignRunError.invalidConfig("minimumMutationRate must be finite and non-negative.")
        }
        guard config.maximumMutationRate.isFinite,
              config.maximumMutationRate >= config.minimumMutationRate else {
            throw LearningCampaignRunError.invalidConfig("maximumMutationRate must be no smaller than minimumMutationRate.")
        }
        guard config.minimumMutationNoiseScale.isFinite,
              config.minimumMutationNoiseScale >= 0 else {
            throw LearningCampaignRunError.invalidConfig("minimumMutationNoiseScale must be finite and non-negative.")
        }
        guard config.maximumMutationNoiseScale.isFinite,
              config.maximumMutationNoiseScale >= config.minimumMutationNoiseScale else {
            throw LearningCampaignRunError.invalidConfig("maximumMutationNoiseScale must be no smaller than minimumMutationNoiseScale.")
        }
        if let minimumRewardAverage = config.minimumRewardAverage,
           !minimumRewardAverage.isFinite {
            throw LearningCampaignRunError.invalidConfig("minimumRewardAverage must be finite.")
        }
        guard config.minimumIncumbentImprovement.isFinite,
              config.minimumIncumbentImprovement >= 0 else {
            throw LearningCampaignRunError.invalidConfig("minimumIncumbentImprovement must be finite and non-negative.")
        }
        if let minimumNoveltyScore = config.minimumNoveltyScore,
           (!minimumNoveltyScore.isFinite || minimumNoveltyScore < 0) {
            throw LearningCampaignRunError.invalidConfig("minimumNoveltyScore must be finite and non-negative.")
        }
        guard config.resourceSampleSeconds.isFinite,
              config.resourceSampleSeconds >= 0 else {
            throw LearningCampaignRunError.invalidConfig("resourceSampleSeconds must be finite and non-negative.")
        }
        guard config.hoverScale.isFinite, config.hoverScale > 0 else {
            throw LearningCampaignRunError.invalidConfig("hoverScale must be finite and greater than 0.")
        }
        let profile = try TaskEvaluationProfile.profile(task: config.task.rawValue)
        if !config.qualityGateEnabled, profile.requiresParentCheckpointEvaluation {
            throw LearningCampaignRunError.invalidConfig("quality gate cannot be disabled for \(profile.task).")
        }
        _ = try validateSuites(config.suites)
    }

    private func rejectNonEmptyArtifactRootIfNeeded(_ config: LearningCampaignRunConfig) throws {
        guard !config.allowsNonEmptyArtifactRoot else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: config.artifactRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: config.artifactRoot,
            includingPropertiesForKeys: nil,
            options: []
        )
        guard contents.isEmpty else {
            throw LearningCampaignRunError.artifactRootNotEmpty(config.artifactRoot.path)
        }
    }

    private func availableDiskBytes(at root: URL) throws -> Int64 {
        let target = FileManager.default.fileExists(atPath: root.path)
            ? root
            : root.deletingLastPathComponent()
        let values = try FileManager.default.attributesOfFileSystem(forPath: target.path)
        return (values[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    private func retentionPolicy(
        _ mode: LearningCampaignArtifactRetentionMode
    ) -> LearningCampaignArtifactRetentionPolicy {
        switch mode {
        case .full:
            return .full
        case .compact:
            return .compact
        }
    }

    private func progressTotalUnitCount(config: LearningCampaignRunConfig) -> Int64 {
        let seedUnits = max(1, config.seedCount) * 3
        return Int64(max(1, 4 + seedUnits))
    }
}

public struct LearningCampaignCheckpointRegressionChecker: LearningCampaignCheckpointRegressionChecking {
    public let config: LearningCampaignRunConfig
    public let minimumRewardAverage: Double?

    public init(config: LearningCampaignRunConfig, minimumRewardAverage: Double?) {
        self.config = config
        self.minimumRewardAverage = minimumRewardAverage
    }

    public func checkCheckpointRegression(
        label: String,
        checkpointURL: URL,
        artifactRoot: URL,
        plan: LearningCampaignPlan
    ) async throws -> KuyuRegressionSummary {
        let profile = try TaskEvaluationProfile.profile(task: config.task.rawValue)
        _ = label
        _ = plan
        return try await KuyuRegressionRunner().run(config: KuyuRegressionRunConfig(
            controller: .manasMLX,
            snapshotURL: checkpointURL,
            tier: config.tier,
            cutPeriodSteps: config.cutPeriodSteps,
            task: config.task.rolloutTask,
            suites: config.suites,
            episodes: config.episodes,
            workers: config.workers,
            maxSteps: nil,
            maxWallTime: nil,
            modelDescriptorPath: config.modelDescriptorPath,
            artifactRoot: artifactRoot,
            kp: config.kp,
            kd: config.kd,
            yawDamping: config.yawDamping,
            hoverScale: config.hoverScale,
            failOnTruncation: profile.failOnTruncation,
            minimumRewardAverage: minimumRewardAverage,
            useQualityGating: config.qualityGateEnabled
        ))
    }
}

@MainActor
public struct LearningCampaignEvolutionRunner: LearningCampaignEvolutionRunning {
    public let config: LearningCampaignRunConfig
    public let minimumRewardAverage: Double?

    public init(config: LearningCampaignRunConfig, minimumRewardAverage: Double?) {
        self.config = config
        self.minimumRewardAverage = minimumRewardAverage
    }

    public func runEvolution(
        seed: String,
        parentCheckpointURL: URL,
        artifactRoot: URL,
        plan: LearningCampaignPlan
    ) async throws -> EvolutionRunArtifactBundle {
        try await runEvolution(
            seed: seed,
            parentCheckpointURL: parentCheckpointURL,
            artifactRoot: artifactRoot,
            plan: plan,
            onEvent: nil
        )
    }

    public func runEvolution(
        seed: String,
        parentCheckpointURL: URL,
        artifactRoot: URL,
        plan: LearningCampaignPlan,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async throws -> EvolutionRunArtifactBundle {
        let profile = try TaskEvaluationProfile.profile(task: config.task.rawValue)
        let backend = ManasMLXEvolutionBackend(
            rootDirectory: artifactRoot.appendingPathComponent("candidates", isDirectory: true),
            variationProvider: makeVariationProvider()
        )
        let evaluator = LearningCampaignEvolutionRegressionEvaluator(
            task: config.task.rolloutTask,
            tier: config.tier,
            cutPeriodSteps: config.cutPeriodSteps,
            suites: config.suites,
            episodes: config.episodes,
            workers: config.workers,
            modelDescriptorPath: config.modelDescriptorPath,
            artifactRoot: artifactRoot.appendingPathComponent("candidate-evaluations", isDirectory: true),
            minimumRewardAverage: minimumRewardAverage,
            useQualityGating: config.qualityGateEnabled
        )
        let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)
        let seedValue = UInt64(seed) ?? 1
        let result = await orchestrator.run(
            config: EvolutionRunConfig(
                taskID: profile.task,
                descriptorID: config.modelDescriptorPath.isEmpty ? nil : config.modelDescriptorPath,
                descriptorHash: config.modelDescriptorPath.isEmpty ? nil : config.modelDescriptorPath,
                configHash: "\(profile.task)-\(seed)-\(config.suites)-\(config.episodes)-\(config.workers)-\(config.candidateEvaluationConcurrency)-\(config.searchStrategy.rawValue)",
                policyID: "manasMLX",
                populationSize: plan.population,
                generationCount: plan.generations,
                eliteCount: config.eliteCount,
                workerCount: config.workers,
                candidateEvaluationConcurrency: config.candidateEvaluationConcurrency,
                searchStrategy: config.searchStrategy,
                bootstrapSource: .checkpoint,
                worldModelUsage: .disabled,
                antitheticSampling: config.searchStrategy == .antitheticEvolutionStrategy,
                commonRandomSeed: seedValue == 0 ? 1 : seedValue,
                mutationRate: config.mutationRate,
                mutationNoiseScale: config.mutationNoiseScale,
                adaptiveMutation: plan.adaptiveMutation.evolutionConfig,
                parentCheckpointID: parentCheckpointURL.lastPathComponent,
                parentCheckpointURL: parentCheckpointURL
            ),
            gatePolicy: EvolutionGatePolicy(
                eliteCount: config.eliteCount,
                minimumTaskPassRate: profile.minimumTaskPassRate,
                maximumSafetyViolationRate: 0,
                minimumHoldTimeRatio: profile.minimumHoldTimeRatio,
                maximumAltitudeErrorRatio: profile.maximumAltitudeErrorRatio,
                minimumRewardAverage: minimumRewardAverage,
                minimumImprovementOverIncumbent: config.minimumIncumbentImprovement,
                minimumNoveltyScore: config.minimumNoveltyScore
            ),
            artifactDirectory: artifactRoot,
            onEvent: onEvent
        )
        if result.manifest.terminalState == .cancelled || Task.isCancelled {
            throw CancellationError()
        }
        return try EvolutionRunArtifactValidator().loadAndValidate(from: artifactRoot)
    }

    private func makeVariationProvider() -> any ManasMLXGenomeVariationProviding {
        switch config.variation {
        case .copy:
            return ManasMLXFileBackedGenomeVariationProvider()
        case .gaussian:
            return ManasMLXGaussianMutationProvider(config: ManasMLXGaussianMutationConfig(
                noiseScale: Float(config.mutationNoiseScale),
                crossoverEnabled: true
            ))
        }
    }
}

public struct LearningCampaignEvolutionRegressionEvaluator: EvolutionCandidateEvaluating {
    private let task: LearningCampaignRolloutTask
    private let tier: LearningCampaignTier
    private let cutPeriodSteps: UInt64
    private let suites: [Int]
    private let episodes: Int
    private let workers: Int
    private let modelDescriptorPath: String
    private let artifactRoot: URL
    private let minimumRewardAverage: Double?
    private let useQualityGating: Bool

    public init(
        task: LearningCampaignRolloutTask,
        tier: LearningCampaignTier,
        cutPeriodSteps: UInt64,
        suites: [Int],
        episodes: Int,
        workers: Int,
        modelDescriptorPath: String,
        artifactRoot: URL,
        minimumRewardAverage: Double?,
        useQualityGating: Bool
    ) {
        self.task = task
        self.tier = tier
        self.cutPeriodSteps = cutPeriodSteps
        self.suites = suites
        self.episodes = episodes
        self.workers = workers
        self.modelDescriptorPath = modelDescriptorPath
        self.artifactRoot = artifactRoot
        self.minimumRewardAverage = minimumRewardAverage
        self.useQualityGating = useQualityGating
    }

    public func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary {
        guard let checkpointURL = request.candidate.checkpointURL else {
            return failedFitness(request: request, reason: "missing-candidate-checkpoint")
        }
        let candidateRoot = artifactRoot
            .appendingPathComponent("generation-\(request.candidate.generationIndex)", isDirectory: true)
            .appendingPathComponent(request.candidate.candidateID, isDirectory: true)
        let summary = try await KuyuRegressionRunner().run(config: KuyuRegressionRunConfig(
            controller: .manasMLX,
            snapshotURL: checkpointURL,
            tier: tier,
            cutPeriodSteps: cutPeriodSteps,
            task: task,
            suites: suites,
            episodes: episodes,
            workers: workers,
            maxSteps: nil,
            maxWallTime: nil,
            modelDescriptorPath: modelDescriptorPath,
            artifactRoot: candidateRoot,
            kp: 2.0,
            kd: 0.25,
            yawDamping: 0.2,
            hoverScale: 1.0,
            failOnTruncation: false,
            minimumRewardAverage: minimumRewardAverage,
            useQualityGating: useQualityGating
        ))
        return fitness(request: request, regression: summary)
    }

    private func failedFitness(
        request: EvolutionCandidateEvaluationRequest,
        reason: String
    ) -> FitnessSummary {
        FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.candidate.generationIndex,
            candidateID: request.candidate.candidateID,
            taskID: request.config.taskID,
            scalarFitness: -Double.greatestFiniteMagnitude,
            rewardAverage: -Double.greatestFiniteMagnitude,
            taskPassRate: 0,
            safetyViolationRate: 1,
            holdTimeRatio: 0,
            altitudeErrorRatio: nil,
            workerThroughput: 0,
            failureReasons: [reason]
        )
    }

    private func fitness(
        request: EvolutionCandidateEvaluationRequest,
        regression: KuyuRegressionSummary
    ) -> FitnessSummary {
        let totalEpisodes = regression.rolloutSuites.reduce(0) { $0 + $1.episodeCount }
        let totalReward = regression.rolloutSuites.reduce(0.0) { $0 + $1.rewardSum }
        let totalPasses = regression.rolloutSuites.reduce(0) { $0 + $1.taskPassCount }
        let totalFailures = regression.rolloutSuites.reduce(0) {
            $0 + $1.failureCount + $1.cancelledCount
        }
        let rewardAverage = totalEpisodes > 0 ? totalReward / Double(totalEpisodes) : 0
        let taskPassRate = totalEpisodes > 0 ? Double(totalPasses) / Double(totalEpisodes) : 0
        let safetyViolationRate = totalEpisodes > 0 ? Double(totalFailures) / Double(totalEpisodes) : 1
        let holdTimeRatio = averageHoldTimeRatio(regression.rolloutSuites)
        let altitudeErrorRatio = maximumAltitudeErrorRatio(regression.rolloutSuites)
        let throughput = minimumWorkerThroughput(regression.rolloutSuites)
        let scalarFitness = rewardAverage
            + taskPassRate * 100
            + (holdTimeRatio ?? 0) * 10
            - (altitudeErrorRatio ?? 0) * 10
            - safetyViolationRate * 100
        return FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.candidate.generationIndex,
            candidateID: request.candidate.candidateID,
            taskID: request.config.taskID,
            scalarFitness: scalarFitness,
            rewardAverage: rewardAverage,
            taskPassRate: taskPassRate,
            safetyViolationRate: safetyViolationRate,
            holdTimeRatio: holdTimeRatio,
            altitudeErrorRatio: altitudeErrorRatio,
            energyPenalty: nil,
            noveltyScore: nil,
            teacherDelta: nil,
            workerThroughput: throughput,
            failureReasons: regression.gateReport.accepted ? [] : regression.gateReport.reasons
        )
    }

    private func averageHoldTimeRatio(_ entries: [KuyuRegressionRolloutEntry]) -> Double? {
        let ratios = entries.flatMap(\.taskQuality).compactMap { quality -> Double? in
            guard let achieved = quality.achievedHoldTime,
                  let required = quality.requiredHoldTime,
                  required > 0 else {
                return nil
            }
            return achieved / required
        }
        guard !ratios.isEmpty else {
            return nil
        }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    private func maximumAltitudeErrorRatio(_ entries: [KuyuRegressionRolloutEntry]) -> Double? {
        let ratios = entries.flatMap(\.taskQuality).compactMap { quality -> Double? in
            guard let error = quality.maxAltitudeErrorAfterWarmup,
                  let tolerance = quality.tolerance,
                  tolerance > 0 else {
                return nil
            }
            return error / tolerance
        }
        return ratios.max()
    }

    private func minimumWorkerThroughput(_ entries: [KuyuRegressionRolloutEntry]) -> Double? {
        let throughputs = entries.flatMap(\.workerSummaries).map(\.throughput)
        return throughputs.min()
    }
}
