import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuMLXTrainingRuntime
import KuyuTraining
import KuyuUI
import KuyuWorkerRuntime

extension RunLearningCampaign {
  @MainActor
  mutating func run() async throws {
    let robotManifestPath = KuyuUIModelPaths.resolveRobotManifestPath(model)
    let trimmedSource = sourceCheckpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let trimmedContinuationRoot =
      continueFromArtifactRoot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !(trimmedSource.isEmpty == false && trimmedContinuationRoot.isEmpty == false) else {
      throw ValidationError(
        "--source-checkpoint and --continue-from-artifact-root cannot both be set.")
    }
    guard !(resume && trimmedContinuationRoot.isEmpty == false) else {
      throw ValidationError("--resume and --continue-from-artifact-root cannot both be set.")
    }
    guard !(resume && trimmedSource.isEmpty == false) else {
      throw ValidationError("--resume and --source-checkpoint cannot both be set.")
    }
    guard resumeFromGeneration == nil || resume else {
      throw ValidationError("--resume-from-generation requires --resume.")
    }
    if let resumeFromGeneration, resumeFromGeneration < 0 {
      throw ValidationError("--resume-from-generation must be >= 0.")
    }
    let artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
      .standardizedFileURL
    let resumeSource: TrainingResumeSource?
    let freshSourceCheckpointURL: URL?
    if resume {
      resumeSource = .artifactRoot(artifactRoot)
      freshSourceCheckpointURL = nil
      print("[learning-campaign] in-place resume requested artifactRoot=\(artifactRoot.path)")
    } else if trimmedContinuationRoot.isEmpty == false {
      let previousArtifactRoot = URL(fileURLWithPath: trimmedContinuationRoot, isDirectory: true)
        .standardizedFileURL
      guard previousArtifactRoot.path != artifactRoot.path else {
        throw ValidationError(
          "--continue-from-artifact-root must differ from --artifact-root; use --resume for in-place continuation."
        )
      }
      resumeSource = .artifactRoot(previousArtifactRoot)
      freshSourceCheckpointURL = nil
      print(
        "[learning-campaign] continuation requested previousArtifactRoot=\(previousArtifactRoot.path)"
      )
    } else {
      guard !trimmedSource.isEmpty else {
        throw ValidationError("--source-checkpoint or --continue-from-artifact-root is required.")
      }
      resumeSource = nil
      freshSourceCheckpointURL = URL(fileURLWithPath: trimmedSource, isDirectory: true)
        .standardizedFileURL
    }
    if let explorationLogStd,
       !explorationLogStd.isFinite || explorationLogStd < -5 || explorationLogStd >= 0 {
      throw ValidationError("--exploration-log-std must be finite and in [-5, 0).")
    }
    if let reinforcementDualLearningRate,
       !reinforcementDualLearningRate.isFinite || reinforcementDualLearningRate <= 0 {
      throw ValidationError("--reinforcement-dual-learning-rate must be finite and > 0.")
    }
    if let reinforcementInitialLambda,
       !reinforcementInitialLambda.isFinite || reinforcementInitialLambda < 0 {
      throw ValidationError("--reinforcement-initial-lambda must be finite and >= 0.")
    }
    if let reinforcementDualCostLimit,
       !reinforcementDualCostLimit.isFinite || reinforcementDualCostLimit <= 0 {
      throw ValidationError("--reinforcement-dual-cost-limit must be finite and > 0.")
    }
    let selectedTrainingSuites: [Int]?
    if let reinforcementTrainingSuites {
      let parsed = try parseRegressionSuites(reinforcementTrainingSuites)
      guard !parsed.isEmpty else {
        throw ValidationError("--reinforcement-training-suites must list at least one suite.")
      }
      guard searchStressSeverity != nil else {
        throw ValidationError(
          "--reinforcement-training-suites requires --search-stress-severity.")
      }
      selectedTrainingSuites = parsed
    } else {
      selectedTrainingSuites = nil
    }
    let contractResolver = ReferenceQuadrotorLearningCampaignTrainingContractResolver(
      explorationLogStandardDeviation: explorationLogStd,
      observationMotorFeedback: observationMotorFeedback
    )
    let contracts = try contractResolver.contracts(for: task)
    let selectedSeeds = try seeds.map(parseCampaignSeeds)
    let selectedSuites = try parseRegressionSuites(suites)
    let selectedAcceptanceSuites = try parseRegressionSuites(acceptanceSuites)
    guard episodes > 0 else {
      throw ValidationError("--episodes must be greater than zero.")
    }
    guard screeningControlSteps > 0 else {
      throw ValidationError("--screening-control-steps must be greater than zero.")
    }
    if let maxRejectedGenerations, maxRejectedGenerations < 0 {
      throw ValidationError("--max-rejected-generations must be non-negative.")
    }
    if let searchStressSeverity,
       !searchStressSeverity.isFinite || searchStressSeverity <= 0 || searchStressSeverity > 1 {
      throw ValidationError("--search-stress-severity must be in (0, 1].")
    }
    if let acceptanceStressSeverity,
       !acceptanceStressSeverity.isFinite
         || acceptanceStressSeverity <= 0
         || acceptanceStressSeverity > 1 {
      throw ValidationError("--acceptance-stress-severity must be in (0, 1].")
    }
    if absolutePromotion, acceptanceStressSeverity == nil {
      throw ValidationError(
        "--absolute-promotion is a curriculum-rung criterion and requires --acceptance-stress-severity."
      )
    }
    guard acceptanceEpisodes > 0 else {
      throw ValidationError("--acceptance-episodes must be greater than zero.")
    }
    var resolvedPopulation = population
    var resolvedEliteCount = eliteCount
    var resolvedWorkers = workers
    var resolvedCandidateEvaluationConcurrency = candidateEvaluationConcurrency
    if !noAutoParallelism {
      let capacity = LearningCampaignMachineCapacity.current()
      resolvedPopulation = capacity.recommendedPopulation(current: resolvedPopulation)
      let recommendation = capacity.recommendation(
        population: resolvedPopulation,
        suiteCount: selectedSuites.count,
        episodes: episodes
      )
      resolvedEliteCount = min(max(1, resolvedEliteCount), resolvedPopulation)
      resolvedWorkers = recommendation.workerCount
      resolvedCandidateEvaluationConcurrency = recommendation.candidateEvaluationConcurrency
      print(
        "[learning-campaign] auto-parallelism machine=\(capacity.summary) population=\(resolvedPopulation) workers=\(recommendation.workerCount) candidateConcurrency=\(recommendation.candidateEvaluationConcurrency) acceleratedSlots=\(recommendation.totalParallelSlots)/\(capacity.acceleratedParallelSlotBudget)"
      )
    }
    guard let executableURL = Bundle.main.executableURL else {
      throw ValidationError("Unable to resolve the kuyu training worker executable.")
    }
    let executor = ManasMLXTrainingRunProcessExecutor(
      configuration: try ManasMLXTrainingWorkerProcessConfigurationFactory().userCache(
        executableURL: executableURL
      )
    )
    let configuration = TrainingRunConfiguration(
      trainingStageID: "evolution-search",
      trainingStageDisplayName: "Evolution Search",
      trainingStageKind: .evolution,
      searchScenarioSelection: TrainingScenarioSelection(
        suiteIDs: selectedSuites,
        episodesPerSuite: episodes,
        tier: TrainingDeterminismTier(cliTier: tier),
        cutPeriodSteps: cutPeriodSteps,
        explicitSeeds: selectedSeeds,
        evaluationFidelity: .screening(
          maximumControlStepsPerEpisode: screeningControlSteps
        ),
        stressSeverity: searchStressSeverity
      ),
      acceptanceScenarioSelection: TrainingScenarioSelection(
        suiteIDs: selectedAcceptanceSuites,
        episodesPerSuite: acceptanceEpisodes,
        tier: TrainingDeterminismTier(cliTier: tier),
        cutPeriodSteps: cutPeriodSteps,
        explicitSeeds: selectedSeeds,
        evaluationFidelity: .fullScenario,
        stressSeverity: acceptanceStressSeverity
      ),
      resources: TrainingResourcePlan(
        workerCount: resolvedWorkers,
        candidateEvaluationConcurrency: resolvedCandidateEvaluationConcurrency,
        resourceSampleSeconds: resourceSampleSeconds,
        worldExecutionRequirement: worldExecution.requirement(task: task)
      ),
      evolution: TrainingEvolutionSettings(
        eliteCount: resolvedEliteCount,
        // Search refinement always runs at full-scenario fidelity: the evolution
        // gate and terminal artifact validator treat bounded refinement evidence
        // as ineligible, and EvolutionRunConfigValidator rejects such configs.
        // Bounded refinement returns only with multi-fidelity evidence typing.
        candidateRefinement: TrainingCandidateRefinementPolicy(
          evaluationFidelity: .fullScenario
        ),
        searchStrategy: searchStrategy,
        variation: TrainingVariationKind(cliVariation: variation),
        mutation: TrainingMutationSchedule(
          rate: mutationRate,
          noiseScale: mutationNoiseScale,
          adaptiveEnabled: adaptiveMutation,
          increaseFactor: mutationIncreaseFactor,
          decayFactor: mutationDecayFactor,
          minimumRate: minimumMutationRate,
          maximumRate: maximumMutationRate,
          minimumNoiseScale: minimumMutationNoiseScale,
          maximumNoiseScale: maximumMutationNoiseScale
        ),
        minimumIncumbentImprovement: minimumIncumbentImprovement,
        minimumNoveltyScore: minimumNoveltyScore,
        maxConsecutiveRejectedGenerations: maxRejectedGenerations,
        promotionCriterion: absolutePromotion ? .absoluteThreshold : nil
      ),
      qualityGate: TrainingQualityGateSettings(
        enabled: !noQualityGate,
        minimumRewardAverage: minimumRewardAverage
      ),
      reinforcement: TrainingReinforcementSettings(
        warmupEnabled: contracts.supportsReinforcementWarmup && !noReinforcementWarmup,
        requiresTemporalActorCritic: true,
        rolloutDuration: reinforcementWarmupDuration,
        iterations: reinforcementWarmupIterations,
        learningRate: reinforcementWarmupLearningRate,
        maxBatches: reinforcementWarmupMaxBatches,
        dualLearningRate: reinforcementDualLearningRate,
        dualInitialLambda: reinforcementInitialLambda,
        dualCostLimit: reinforcementDualCostLimit,
        trainingSuites: selectedTrainingSuites,
        stopping: try TrainingReinforcementStoppingSettings(
          minimumIterationCount: reinforcementMinimumIterations,
          plateauWindow: reinforcementPlateauWindow,
          unsafeWindow: reinforcementUnsafeWindow
        )
      ),
      control: TrainingControlSettings(
        robotManifestPath: robotManifestPath,
        kp: kp,
        kd: kd,
        yawDamping: yawDamping,
        hoverScale: hoverScale
      ),
      artifacts: TrainingArtifactPolicy(
        retention: TrainingArtifactRetentionKind(cliRetention: artifactRetention),
        allowsNonEmptyArtifactRoot: resume,
        requiresInitialParentPass: !skipInitialParentPass,
        reinforcementTrainingArtifactDirectory: reinforcementArtifactPath.map {
          URL(fileURLWithPath: $0, isDirectory: true)
        },
        resumeInPlace: resume,
        resumeFromGeneration: resumeFromGeneration
      ),
      autonomyDomain: autonomyDomain
    )
    try contracts.validate(reinforcement: configuration.reinforcement)
    let runID = TrainingRunID(artifactRoot.lastPathComponent)
    let lifecycle = TrainingRunLifecycleCoordinator()
    let signalRecorder = LearningCampaignProcessSignal.Recorder()
    let stopSignalMonitor = Self.installStopSignalHandlers { signal in
      await signalRecorder.record(signal)
      await lifecycle.requestCancellation()
    }
    defer {
      stopSignalMonitor.cancel()
      Self.restoreStopSignalHandlers()
    }
    let handle: any TrainingRunHandle
    if let resumeSource {
      handle = try await executor.resume(
        TrainingResumeRequest(
          runID: runID,
          source: resumeSource,
          destinationArtifactRoot: artifactRoot,
          taskProfileID: contracts.taskProfileID,
          policyContract: contracts.policyContract,
          actionContract: contracts.actionContract,
          seedCount: seedCount,
          populationSize: resolvedPopulation,
          generationLimit: generations,
          configuration: configuration
        ))
    } else {
      guard let sourceCheckpointURL = freshSourceCheckpointURL else {
        throw ValidationError("Fresh campaign source checkpoint resolution failed.")
      }
      let sourceBundle = try ManasMLXModelBundleReferenceResolver().bundleReference(
        at: sourceCheckpointURL,
        kind: .source
      )
      handle = try await executor.start(
        TrainingRunRequest(
          runID: runID,
          artifactRoot: artifactRoot,
          taskProfileID: contracts.taskProfileID,
          policyContract: contracts.policyContract,
          actionContract: contracts.actionContract,
          sourceBundle: sourceBundle,
          seedCount: seedCount,
          populationSize: resolvedPopulation,
          generationLimit: generations,
          configuration: configuration
        ))
    }
    try await lifecycle.register(handle)
    async let completedSummary = lifecycle.waitForTermination()
    for await event in handle.events {
      _ = printTrainingRunEvent(event)
    }
    let summary = try await completedSummary
    print("[learning-campaign] artifacts path=\(artifactRoot.path)")
    if let signal = await signalRecorder.receivedSignal() {
      print(
        "[learning-campaign] cancelled - durable artifacts written. Resume with: --resume --artifact-root \(artifactRoot.path)"
      )
      throw ExitCode(signal.exitCode)
    }
    let disposition = TrainingRunWorkerProcessDisposition(summary: summary)
    switch disposition {
    case .success:
      return
    case .rejection:
      let reasons = summary.failureReasons.isEmpty
        ? "checkpoint-not-accepted"
        : summary.failureReasons.joined(separator: ", ")
      FileHandle.standardError.write(
        Data("[learning-campaign] rejected: \(reasons)\n".utf8)
      )
      throw ExitCode(disposition.exitStatus)
    case .cancellation:
      throw ExitCode(disposition.exitStatus)
    case .failure, .invalidOutcome:
      let reasons = summary.failureReasons.isEmpty
        ? summary.terminalState.rawValue
        : summary.failureReasons.joined(separator: ", ")
      FileHandle.standardError.write(
        Data("[learning-campaign] failed: \(reasons)\n".utf8)
      )
      throw ExitCode(disposition.exitStatus)
    }
  }
}
