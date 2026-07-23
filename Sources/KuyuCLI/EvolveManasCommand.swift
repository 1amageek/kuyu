import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXEvolution
import KuyuMLXReferenceQuadrotor
import KuyuTraining

enum EvolutionVariationChoice: String, CaseIterable, ExpressibleByArgument {
    case copy
    case gaussian
}

enum EvolutionEvaluationChoice: String, CaseIterable, ExpressibleByArgument {
    case regression
    case candidateOnly
}

enum EvolutionSearchStrategyChoice: String, CaseIterable, ExpressibleByArgument {
    case genetic
    case antitheticEvolutionStrategy
    case qualityDiversity

    var trainingStrategy: EvolutionSearchStrategy {
        switch self {
        case .genetic:
            return .genetic
        case .antitheticEvolutionStrategy:
            return .antitheticEvolutionStrategy
        case .qualityDiversity:
            return .qualityDiversity
        }
    }
}

enum EvolutionBootstrapSourceChoice: String, CaseIterable, ExpressibleByArgument {
    case checkpoint
    case teacher
    case demonstration
    case none

    var trainingSource: EvolutionBootstrapSource {
        switch self {
        case .checkpoint:
            return .checkpoint
        case .teacher:
            return .teacher
        case .demonstration:
            return .demonstration
        case .none:
            return .none
        }
    }
}

enum EvolutionWorldModelUsageChoice: String, CaseIterable, ExpressibleByArgument {
    case disabled
    case evaluationAssist
    case imaginationAssist

    var trainingUsage: EvolutionWorldModelUsage {
        switch self {
        case .disabled:
            return .disabled
        case .evaluationAssist:
            return .evaluationAssist
        case .imaginationAssist:
            return .imaginationAssist
        }
    }
}

struct EvolveManas: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "evolve-manas",
        abstract: "Run a Kuyu-backed evolutionary harness over ManasMLX checkpoint candidates."
    )

    @Option(help: "Task to optimize: lift or singleLift.")
    var task: RolloutTaskChoice = .lift

    @Option(help: "Source ManasMLX model snapshot directory.")
    var snapshot: String

    @Option(help: "Population size per generation.")
    var population: Int = 100

    @Option(help: "Maximum generation budget. Normal completion should come from convergence or gate acceptance.")
    var generations: Int = 1_000

    @Option(name: .customLong("elite-count"), help: "Number of candidates selected as parents.")
    var eliteCount: Int = 10

    @Option(help: "Worker count for rollout regression.")
    var workers: Int = 1

    @Option(name: .customLong("candidate-evaluation-concurrency"), help: "Maximum Manas candidate evaluations to run concurrently.")
    var candidateEvaluationConcurrency: Int = 100

    @Flag(name: .customLong("no-auto-parallelism"), help: "Disable machine-optimized population and evaluation concurrency.")
    var noAutoParallelism: Bool = false

    @Option(help: "Comma-separated M2 suite list: 6,7,8.")
    var suites: String = "6"

    @Option(help: "Episodes per candidate regression.")
    var episodes: Int = 1

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Robot manifest path.")
    var model: String = ""

    @Option(name: .customLong("artifact-root"), help: "Directory where evolution artifacts are written.")
    var artifactRootPath: String?

    @Option(name: .customLong("mutation-rate"), help: "Mutation rate passed to the ManasMLX variation provider.")
    var mutationRate: Double = 0.14

    @Option(name: .customLong("mutation-noise-scale"), help: "Gaussian mutation noise scale.")
    var mutationNoiseScale: Double = 0.025

    @Option(name: .customLong("search-strategy"), help: "Evolution search strategy: genetic, antitheticEvolutionStrategy, or qualityDiversity.")
    var searchStrategy: EvolutionSearchStrategyChoice = .genetic

    @Option(name: .customLong("bootstrap-source"), help: "Bootstrap source metadata: checkpoint, teacher, demonstration, or none.")
    var bootstrapSource: EvolutionBootstrapSourceChoice = .checkpoint

    @Option(name: .customLong("world-model-usage"), help: "World-model role metadata: disabled, evaluationAssist, or imaginationAssist.")
    var worldModelUsage: EvolutionWorldModelUsageChoice = .disabled

    @Option(name: .customLong("common-random-seed"), help: "Common seed used for ES-style paired perturbations.")
    var commonRandomSeed: UInt64 = 1

    @Flag(name: .customLong("antithetic-sampling"), help: "Use paired positive/negative perturbations with common random seeds.")
    var antitheticSampling: Bool = false

    @Flag(name: .customLong("adaptive-mutation"), inversion: .prefixedNo, help: "Adapt mutation rate and noise scale based on generation gate results.")
    var adaptiveMutation: Bool = true

    @Option(help: "Candidate variation mode: gaussian or copy.")
    var variation: EvolutionVariationChoice = .gaussian

    @Option(help: "Candidate evaluation mode: regression.")
    var evaluation: EvolutionEvaluationChoice = .regression

    @Flag(name: .customLong("no-crossover"), help: "Disable elite checkpoint averaging before mutation.")
    var noCrossover: Bool = false

    @Option(name: .customLong("min-reward-average"), help: "Override task default minimum reward average.")
    var minimumRewardAverage: Double?

    @Option(name: .customLong("min-incumbent-improvement"), help: "Minimum strict scalar-fitness improvement over the incumbent checkpoint.")
    var minimumIncumbentImprovement: Double = 0

    @Option(name: .customLong("min-novelty-score"), help: "Minimum novelty score required for a candidate to enter the evolution archive.")
    var minimumNoveltyScore: Double?

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for ManasMLX rollout.")
    var noQualityGate: Bool = false

    @MainActor
    mutating func run() async throws {
        guard task == .lift || task == .singleLift else {
            throw ValidationError("evolve-manas currently supports lift and singleLift.")
        }
        guard population > 0 else {
            throw ValidationError("--population must be greater than 0.")
        }
        guard generations > 0 else {
            throw ValidationError("--generations must be greater than 0.")
        }
        guard eliteCount > 0, eliteCount <= population else {
            throw ValidationError("--elite-count must be greater than 0 and no larger than --population.")
        }
        guard workers > 0 else {
            throw ValidationError("--workers must be greater than 0.")
        }
        guard candidateEvaluationConcurrency > 0, candidateEvaluationConcurrency <= population else {
            throw ValidationError("--candidate-evaluation-concurrency must be greater than 0 and no larger than --population.")
        }
        guard episodes > 0 else {
            throw ValidationError("--episodes must be greater than 0.")
        }
        guard mutationRate.isFinite, mutationRate >= 0 else {
            throw ValidationError("--mutation-rate must be finite and non-negative.")
        }
        guard mutationNoiseScale.isFinite, mutationNoiseScale >= 0 else {
            throw ValidationError("--mutation-noise-scale must be finite and non-negative.")
        }
        if let minimumRewardAverage, !minimumRewardAverage.isFinite {
            throw ValidationError("--min-reward-average must be finite when specified.")
        }
        guard evaluation == .regression else {
            throw ValidationError("--evaluation candidateOnly is unsupported because evolution artifacts require physical regression evidence.")
        }
        let evolutionProfile = try TaskEvaluationProfile.profile(task: task.rawValue)
        let effectiveMinimumRewardAverage = try ReferenceQuadrotorRegressionQualityGatePolicy.minimumRewardAverage(
            override: minimumRewardAverage,
            task: evolutionProfile.task
        )
        guard minimumIncumbentImprovement.isFinite, minimumIncumbentImprovement >= 0 else {
            throw ValidationError("--min-incumbent-improvement must be finite and non-negative.")
        }
        if let minimumNoveltyScore,
           (!minimumNoveltyScore.isFinite || minimumNoveltyScore < 0) {
            throw ValidationError("--min-novelty-score must be finite and non-negative when specified.")
        }
        let trimmedSnapshot = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSnapshot.isEmpty else {
            throw ValidationError("--snapshot is required.")
        }
        let snapshotURL = URL(fileURLWithPath: trimmedSnapshot, isDirectory: true)
        try checkEvolutionInputs(snapshotURL: snapshotURL)
        let artifactRoot: URL
        if let artifactRootPath, !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
        } else {
            artifactRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-evolve-manas-\(UUID().uuidString)", isDirectory: true)
        }
        let selectedSuites = try parseRegressionSuites(suites)
        let effectivePopulation: Int
        let effectiveEliteCount: Int
        let effectiveWorkers: Int
        let effectiveCandidateEvaluationConcurrency: Int
        if !noAutoParallelism {
            let capacity = LearningCampaignMachineCapacity.current()
            effectivePopulation = capacity.recommendedPopulation(current: population)
            effectiveEliteCount = min(eliteCount, effectivePopulation)
            let recommendation = capacity.recommendation(
                population: effectivePopulation,
                suiteCount: selectedSuites.count,
                episodes: episodes
            )
            effectiveWorkers = recommendation.workerCount
            effectiveCandidateEvaluationConcurrency = recommendation.candidateEvaluationConcurrency
            print("[evolve] auto-parallelism machine=\(capacity.summary) population=\(effectivePopulation) workers=\(effectiveWorkers) candidateConcurrency=\(effectiveCandidateEvaluationConcurrency) acceleratedSlots=\(recommendation.totalParallelSlots)/\(capacity.acceleratedParallelSlotBudget)")
        } else {
            effectivePopulation = population
            effectiveEliteCount = eliteCount
            effectiveWorkers = workers
            effectiveCandidateEvaluationConcurrency = candidateEvaluationConcurrency
        }
        let backend = ManasMLXEvolutionBackend(
            rootDirectory: artifactRoot.appendingPathComponent("candidates", isDirectory: true),
            variationProvider: makeVariationProvider()
        )
        let evaluator: any EvolutionCandidateEvaluating = ReferenceQuadrotorEvolutionRegressionEvaluator(
            task: learningCampaignRolloutTask(from: task),
            tier: learningCampaignTier(from: tier),
            cutPeriodSteps: cutPeriodSteps,
            suites: selectedSuites,
            episodes: episodes,
            workers: effectiveWorkers,
            robotManifestPath: model,
            minimumRewardAverage: effectiveMinimumRewardAverage,
            useQualityGating: !noQualityGate
        )
        let orchestrator = EvolutionRunOrchestrator(
            backend: backend,
            evaluator: evaluator
        )
        _ = await orchestrator.run(
            config: EvolutionRunConfig(
                taskID: task.rawValue,
                robotManifestID: model.isEmpty ? nil : model,
                robotManifestHash: model.isEmpty ? nil : model,
                configHash: "\(task.rawValue)-\(suites)-\(episodes)-\(effectiveWorkers)-\(effectiveCandidateEvaluationConcurrency)-\(searchStrategy.rawValue)",
                policyID: "manasMLX",
                populationSize: effectivePopulation,
                generationCount: generations,
                eliteCount: effectiveEliteCount,
                workerCount: effectiveWorkers,
                candidateEvaluationConcurrency: effectiveCandidateEvaluationConcurrency,
                searchStrategy: searchStrategy.trainingStrategy,
                bootstrapSource: bootstrapSource.trainingSource,
                worldModelUsage: worldModelUsage.trainingUsage,
                antitheticSampling: antitheticSampling,
                commonRandomSeed: commonRandomSeed,
                mutationRate: mutationRate,
                mutationNoiseScale: mutationNoiseScale,
                adaptiveMutation: EvolutionAdaptiveMutationConfig(enabled: adaptiveMutation),
                // Attitude and A1 stress suites are not tensor-world capable.
                worldExecutionRequirement: task == .attitude
                    ? .preferAcceleratorSharedWorld
                    : .acceleratorSharedWorld,
                parentCheckpointID: snapshotURL.lastPathComponent,
                parentCheckpointURL: snapshotURL
            ),
            gatePolicy: EvolutionGatePolicy(
                eliteCount: effectiveEliteCount,
                minimumTaskPassRate: evolutionProfile.minimumTaskPassRate,
                maximumSafetyViolationRate: 0,
                minimumHoldTimeRatio: evolutionProfile.minimumHoldTimeRatio,
                maximumAltitudeErrorRatio: evolutionProfile.maximumAltitudeErrorRatio,
                minimumRewardAverage: effectiveMinimumRewardAverage,
                minimumImprovementOverIncumbent: minimumIncumbentImprovement,
                minimumNoveltyScore: minimumNoveltyScore
            ),
            artifactDirectory: artifactRoot
        )
        let artifactReader = KuyuCLITrainingArtifactReader()
        let artifactSnapshot = try artifactReader.validatedEvolutionPublication(in: artifactRoot)
        let artifacts = artifactSnapshot.artifacts
        let publication = artifactSnapshot.publication
        let displayBestCandidateID = artifacts.eliteArchive.bestCandidateID
            ?? artifacts.generations.last?.bestCandidateID
            ?? "n/a"
        let displayBestFitness = artifacts.eliteArchive.bestFitness
            ?? artifacts.generations.last?.bestFitness
        print("[evolve] artifacts path=\(artifactRoot.path)")
        print("[evolve] terminal=\(artifacts.manifest.terminalState.rawValue) variation=\(variation.rawValue) evaluation=\(evaluation.rawValue) generations=\(artifacts.generations.count) candidates=\(artifacts.candidates.count) best=\(displayBestCandidateID) bestFitness=\(formatOptional(displayBestFitness)) elites=\(artifacts.eliteArchive.eliteCandidateIDs.joined(separator: ","))")
        print("[evolve] acceptedCheckpoint=\(publication.acceptedCheckpointPath ?? "n/a") acceptedCandidate=\(publication.acceptedCandidateID ?? "n/a") bestCandidate=\(publication.bestCandidateID ?? "n/a") bestCheckpoint=\(publication.bestCheckpointPath ?? "n/a") publishReasons=\(publication.reasons.joined(separator: ",")) decision=\(publication.decisionPath)")
        printEvolutionSearchSummary(artifacts: artifacts, adaptiveMutation: adaptiveMutation)
        do {
            try artifactReader.requireAcceptedEvolutionCheckpoint(publication)
        } catch KuyuCLITrainingArtifactReaderError.evolutionCheckpointNotAccepted(_) {
            throw ExitCode.failure
        }
    }

    private func printEvolutionSearchSummary(
        artifacts: EvolutionRunArtifactBundle,
        adaptiveMutation: Bool
    ) {
        let manifest = artifacts.manifest
        let finalGeneration = artifacts.generations.last
        let incumbentCandidateID = artifacts.candidates.first { $0.isIncumbent == true }?.candidateID
        let incumbentFitness = incumbentCandidateID.flatMap { candidateID in
            artifacts.fitness.first { $0.candidateID == candidateID }?.scalarFitness
        }
        let bestQDCell = artifacts.qualityDiversityArchive.cells.max { lhs, rhs in
            if lhs.fitness == rhs.fitness {
                return lhs.candidateID > rhs.candidateID
            }
            return lhs.fitness < rhs.fitness
        }
        let bestFitness = artifacts.eliteArchive.bestFitness ?? finalGeneration?.bestFitness
        let bestVsIncumbentDelta = zipOptional(
            bestFitness,
            incumbentFitness
        ).map { best, incumbent in best - incumbent }
        print(
            "[evolve] strategy=\(manifest.searchStrategy.rawValue) bootstrap=\(manifest.bootstrapSource.rawValue) worldModel=\(manifest.worldModelUsage.rawValue) antithetic=\(manifest.antitheticSampling) commonSeed=\(manifest.commonRandomSeed) adaptiveMutation=\(adaptiveMutation)"
        )
        print(
            "[evolve] incumbent=\(incumbentCandidateID ?? "n/a") incumbentFitness=\(formatOptional(incumbentFitness)) bestVsIncumbentDelta=\(formatOptional(bestVsIncumbentDelta))"
        )
        print(
            "[evolve] qdCells=\(artifacts.qualityDiversityArchive.cells.count) qdBest=\(bestQDCell?.candidateID ?? "n/a") qdBestFitness=\(formatOptional(bestQDCell?.fitness)) qdArchive=\(artifacts.artifactDirectory.appendingPathComponent(EvolutionQualityDiversityArchive.fileName).path)"
        )
        print(
            "[evolve] finalMutationRate=\(formatOptional(finalGeneration?.mutationRate)) finalMutationNoiseScale=\(formatOptional(finalGeneration?.mutationNoiseScale)) finalQDCells=\(finalGeneration?.qualityDiversityCellCount ?? 0)"
        )
    }

    @MainActor
    private func makeVariationProvider() -> any ManasMLXGenomeVariationProviding {
        switch variation {
        case .copy:
            return ManasMLXFileBackedGenomeVariationProvider()
        case .gaussian:
            return ManasMLXGaussianMutationProvider(config: ManasMLXGaussianMutationConfig(
                noiseScale: 1,
                crossoverEnabled: !noCrossover
            ))
        }
    }

    @MainActor
    private func checkEvolutionInputs(snapshotURL: URL) throws {
        let preflight = try ManasMLXRuntimeReadinessService().report(
            for: ManasMLXRuntimeReadinessRequest(
                robotManifestPath: model,
                sourceCheckpointURL: snapshotURL,
                requireSourceCheckpoint: true
            )
        )
        print("[evolve] preflight mlx=\(preflight.mlxRuntimeReady) robotManifestLoaded=\(preflight.robotManifestLoaded) sourceCheckpointLoadable=\(preflight.sourceCheckpointLoadable)")
    }
}

private func zipOptional<A, B>(_ lhs: A?, _ rhs: B?) -> (A, B)? {
    guard let lhs, let rhs else {
        return nil
    }
    return (lhs, rhs)
}
