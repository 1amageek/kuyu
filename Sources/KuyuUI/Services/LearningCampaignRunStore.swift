import Foundation
import KuyuMLX
import KuyuMLXCampaignContracts
import KuyuTraining

public enum LearningCampaignVectorizedBatchKind: String, Sendable, Codable, Equatable {
  case variation
  case evaluation
}

public struct LearningCampaignVectorizedBatchState: Identifiable, Sendable, Equatable {
  public let id: String
  public let kind: LearningCampaignVectorizedBatchKind
  public let seed: String
  public let generationIndex: Int
  public let candidateCount: Int
  public let completedCandidateCount: Int
  public let elapsedSeconds: Double
  public let acceleratorDevice: String
  public let policyExecutionMode: String?
  public let observationExecutionMode: String?
  public let worldExecutionMode: String?
  public let actionEncoding: String?
  public let worldActiveActionDimension: Int?
  public let artifactPath: String
  public let bestFitness: Double?

  init(
    kind: LearningCampaignVectorizedBatchKind,
    seed: String,
    generationIndex: Int,
    candidateCount: Int,
    completedCandidateCount: Int,
    elapsedSeconds: Double,
    acceleratorDevice: String,
    policyExecutionMode: String?,
    observationExecutionMode: String?,
    worldExecutionMode: String?,
    actionEncoding: String?,
    worldActiveActionDimension: Int?,
    artifactPath: String,
    bestFitness: Double?
  ) {
    self.id = "\(kind.rawValue)-\(seed)-g\(generationIndex)-\(artifactPath)"
    self.kind = kind
    self.seed = seed
    self.generationIndex = generationIndex
    self.candidateCount = candidateCount
    self.completedCandidateCount = completedCandidateCount
    self.elapsedSeconds = elapsedSeconds
    self.acceleratorDevice = acceleratorDevice
    self.policyExecutionMode = policyExecutionMode
    self.observationExecutionMode = observationExecutionMode
    self.worldExecutionMode = worldExecutionMode
    self.actionEncoding = actionEncoding
    self.worldActiveActionDimension = worldActiveActionDimension
    self.artifactPath = artifactPath
    self.bestFitness = bestFitness
  }

  public var executionSummary: String {
    switch kind {
    case .variation:
      return "mlx-stacked-variation"
    case .evaluation:
      let policy = policyExecutionMode ?? "unknown-policy"
      let observation = observationExecutionMode ?? "unknown-observation"
      let world = worldExecutionMode ?? "unknown-world"
      let action = actionEncoding ?? "unknown-action"
      if let worldActiveActionDimension {
        return
          "\(policy) / \(observation) / \(world) / \(action) active=\(worldActiveActionDimension)"
      }
      return "\(policy) / \(observation) / \(world) / \(action)"
    }
  }
}

public struct LearningCampaignRunStoreState: Sendable, Equatable {
  /// The runtime-owned progress snapshot is built once from the artifact
  /// records before the state crosses into SwiftUI.
  public let artifactDirectory: URL
  public let plan: LearningCampaignPlan?
  public let evolutionManifest: EvolutionRunManifest?
  public let status: LearningCampaignStatus?
  public let summary: LearningCampaignSummary?
  /// Historical observations. Neither is current campaign state unless a new
  /// validation run is performed against the current artifacts.
  public let strictValidation: LearningCampaignValidation?
  public let diagnosticValidation: LearningCampaignValidation?
  public let strictValidationReceiptIssue: String?
  public let diagnosticValidationReceiptIssue: String?
  public let retention: LearningCampaignArtifactRetentionSummary?
  public let accelerator: LearningCampaignAcceleratorSnapshot?
  public let vectorizedBatches: [LearningCampaignVectorizedBatchState]
  public let progress: LearningCampaignProgressSnapshot

  public init(
    artifactDirectory: URL,
    plan: LearningCampaignPlan?,
    status: LearningCampaignStatus?,
    summary: LearningCampaignSummary?,
    validation: LearningCampaignValidation?,
    retention: LearningCampaignArtifactRetentionSummary?,
    accelerator: LearningCampaignAcceleratorSnapshot?,
    progressEvents: [LearningCampaignProgressEvent],
    generations: [LearningCampaignGenerationState],
    candidates: [LearningCampaignCandidateState],
    vectorizedBatches: [LearningCampaignVectorizedBatchState],
    acceptedCheckpoints: [LearningCampaignAcceptedCheckpointState],
    evolutionManifest: EvolutionRunManifest? = nil,
    validationReceiptIssue: String? = nil,
    strictValidation: LearningCampaignValidation? = nil,
    diagnosticValidation: LearningCampaignValidation? = nil,
    strictValidationReceiptIssue: String? = nil,
    diagnosticValidationReceiptIssue: String? = nil
  ) {
    self.artifactDirectory = artifactDirectory
    self.plan = plan
    self.evolutionManifest = evolutionManifest
    self.status = status
    self.summary = summary
    self.strictValidation = strictValidation
      ?? (validation?.policy.isStrict == true ? validation : nil)
    self.diagnosticValidation = diagnosticValidation
      ?? (validation?.policy.isStrict == false ? validation : nil)
    self.strictValidationReceiptIssue = strictValidationReceiptIssue
      ?? (validation?.policy.isStrict != false ? validationReceiptIssue : nil)
    self.diagnosticValidationReceiptIssue = diagnosticValidationReceiptIssue
      ?? (validation?.policy.isStrict == false ? validationReceiptIssue : nil)
    self.retention = retention
    self.accelerator = accelerator
    self.vectorizedBatches = vectorizedBatches
    self.progress = LearningCampaignProgressSnapshot(
      plan: plan,
      status: status,
      summary: summary,
      validation: nil,
      progressEvents: progressEvents,
      generations: generations,
      candidates: candidates,
      acceptedCheckpoints: acceptedCheckpoints
    )
  }

  public var progressEvents: [LearningCampaignProgressEvent] {
    progress.progressEvents
  }

  public var generations: [LearningCampaignGenerationState] {
    progress.generations
  }

  public var candidates: [LearningCampaignCandidateState] {
    progress.candidates
  }

  public var acceptedCheckpoints: [LearningCampaignAcceptedCheckpointState] {
    progress.acceptedCheckpoints
  }

  public var latestEvent: LearningCampaignProgressEvent? {
    progressEvents.last
  }

  public var task: String {
    plan?.task ?? evolutionManifest?.taskID ?? "--"
  }

  public var trainingStageLabel: String {
    if let displayName = plan?.trainingStageDisplayName, !displayName.isEmpty {
      return displayName
    }
    if let stageID = plan?.trainingStageID, !stageID.isEmpty {
      return stageID
    }
    return "--"
  }

  public var trainingStageKindLabel: String {
    plan?.trainingStageKind?.rawValue ?? "--"
  }

  public var hasTrainingStageIdentity: Bool {
    trainingStageLabel != "--" || trainingStageKindLabel != "--"
  }

  public var suiteSummary: String {
    guard let plan else { return "--" }
    let search = plan.searchSuites.joined(separator: ",")
    let acceptance = plan.acceptanceSuites.joined(separator: ",")
    return "search \(search) | acceptance \(acceptance)"
  }

  public var seedCount: Int {
    summary?.seedCount ?? plan?.seeds.count ?? (evolutionManifest == nil ? 0 : 1)
  }

  public var acceptedCount: Int {
    if let summary {
      return summary.acceptedCount
    }
    return acceptedCheckpoints.filter(\.accepted).count
  }

  public var finalCheckpoint: String? {
    summary?.finalCheckpoint
  }

  public var statusLabel: String {
    status?.status ?? latestEvent?.status ?? "running"
  }

  public var validationLabel: String {
    if strictValidationReceiptIssue != nil { return "recorded strict receipt invalid" }
    if strictValidation == nil, diagnosticValidationReceiptIssue != nil {
      return "recorded diagnostic receipt invalid"
    }
    guard let validation else { return "--" }
    let result = validation.valid ? "valid" : "invalid"
    return validation.policy.isStrict
      ? "recorded strict \(result)"
      : "recorded diagnostic \(result)"
  }

  public var validation: LearningCampaignValidation? {
    strictValidation ?? diagnosticValidation
  }

  public var validationReceiptIssue: String? {
    let issues = [strictValidationReceiptIssue, diagnosticValidationReceiptIssue]
      .compactMap { $0 }
    return issues.isEmpty ? nil : issues.joined(separator: " | ")
  }

  public var bestDelta: Double? {
    let deltas = generations.compactMap(\.bestVsIncumbentDelta)
    return deltas.max()
  }

  public var latestGenerations: [LearningCampaignGenerationState] {
    generations
      .sorted { lhs, rhs in
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
        return lhs.generationIndex > rhs.generationIndex
      }
  }

  public var plannedGenerationCount: Int {
    plan?.generations
      ?? evolutionManifest?.generationCount
      ?? generations.map(\.generationIndex).max().map { $0 + 1 }
      ?? 0
  }

  public var latestCompletedGenerationIndex: Int? {
    progress.latestCompletedGenerationIndex
  }

  public var completedGenerationCount: Int {
    latestCompletedGenerationIndex.map { $0 + 1 } ?? generations.count
  }

  public var liveCandidateEvaluationCount: Int {
    progress.liveCandidateEvaluationCount
  }

  public var liveEpisodeCount: Int {
    liveCandidateEvaluationCount * episodeMultiplier
  }

  public var plannedCandidateEvaluationCount: Int {
    if let plan {
      return max(1, plan.seeds.count) * max(1, plan.population) * max(1, plan.generations)
    }
    if let evolutionManifest {
      return evolutionManifest.populationSize * evolutionManifest.generationCount
    }
    return max(0, liveCandidateEvaluationCount)
  }

  public var campaignProgressFraction: Double {
    guard status?.status.lowercased() != "succeeded" else { return 1 }
    guard status?.status.lowercased() != "completed" else { return 1 }
    let plannedCandidates = plannedCandidateEvaluationCount
    if plannedCandidates > 0 {
      return min(0.999, max(0, Double(liveCandidateEvaluationCount) / Double(plannedCandidates)))
    }
    let plannedGenerations = plannedGenerationCount
    guard plannedGenerations > 0 else { return 0 }
    return min(0.999, max(0, Double(completedGenerationCount) / Double(plannedGenerations)))
  }

  public var bestFitness: Double? {
    progress.bestFitness
  }

  public var initialBestFitness: Double? {
    progress.initialBestFitness
  }

  public var bestFitnessDeltaFromInitial: Double? {
    guard let bestFitness, let initialBestFitness else { return nil }
    return bestFitness - initialBestFitness
  }

  public var bestTaskPassRate: Double? {
    progress.bestTaskPassRate
  }

  public var bestHoldTimeRatio: Double? {
    progress.bestHoldTimeRatio
  }

  public var bestAltitudeErrorRatio: Double? {
    progress.bestAltitudeErrorRatio
  }

  public var liveBestFitnessSamples: [MetricSample] {
    progress.liveBestFitnessSamples.map { sample in
      MetricSample(time: sample.time, value: sample.value)
    }
  }

  public var liveRewardAverageSamples: [MetricSample] {
    progress.liveRewardAverageSamples.map { sample in
      MetricSample(time: sample.time, value: sample.value)
    }
  }

  public var liveTaskPassRateSamples: [MetricSample] {
    progress.liveTaskPassRateSamples.map { sample in
      MetricSample(time: sample.time, value: sample.value)
    }
  }

  public var liveHoldTimeRatioSamples: [MetricSample] {
    progress.liveHoldTimeRatioSamples.map { sample in
      MetricSample(time: sample.time, value: sample.value)
    }
  }

  public var liveAltitudeErrorRatioSamples: [MetricSample] {
    progress.liveAltitudeErrorRatioSamples.map { sample in
      MetricSample(time: sample.time, value: sample.value)
    }
  }

  public var liveGenerationCountSamples: [MetricSample] {
    progress.liveGenerationCountSamples.map { sample in
      MetricSample(time: sample.time, value: sample.value)
    }
  }

  public var liveEpisodeSamples: [MetricSample] {
    progress.liveEpisodeSamples.map { sample in
      MetricSample(time: sample.time, value: sample.value)
    }
  }

  public var livePopulationDiversitySamples: [MetricSample] {
    progress.livePopulationDiversitySamples.map { sample in
      MetricSample(time: sample.time, value: sample.value)
    }
  }

  public var populationDiversity: Double? {
    progress.livePopulationDiversitySamples.last?.value
  }

  public var latestLiveCandidate: LearningCampaignProgressEvent? {
    progress.latestLiveCandidate
  }

  public var latestWorkProgress: TrainingWorkProgress? {
    progress.latestWorkProgress
  }

  public var latestReinforcementIteration: LearningCampaignReinforcementIterationProgress? {
    progressEvents.compactMap(\.reinforcementIteration).max {
      if $0.globalIteration != $1.globalIteration {
        return $0.globalIteration < $1.globalIteration
      }
      return $0.timestamp < $1.timestamp
    }
  }

  public var activeReinforcementWorkProgress: TrainingWorkProgress? {
    guard progress.lifecycleStage == .reinforcing,
      let work = latestWorkProgress,
      work.unit.identifier == "rr-ppo-iterations",
      !work.state.isTerminal
    else {
      return nil
    }
    return work
  }

  public var activeReinforcementIteration: LearningCampaignReinforcementIterationProgress? {
    guard activeReinforcementWorkProgress != nil else { return nil }
    return latestReinforcementIteration
  }

  public var currentScenarioProgress: TrainingWorkProgress? {
    progress.currentScenarioProgress
  }

  public var currentControlStepProgress: TrainingWorkProgress? {
    progress.currentControlStepProgress
  }

  public var maxRequestedCandidateConcurrency: Int {
    vectorizedBatches.map(\.candidateCount).max()
      ?? candidates.compactMap(\.requestedConcurrency).max()
      ?? plan?.candidateEvaluationConcurrency
      ?? evolutionManifest?.candidateEvaluationConcurrency
      ?? 1
  }

  public var maxActiveCandidateEvaluations: Int {
    vectorizedBatches.map(\.completedCandidateCount).max()
      ?? candidates.compactMap(\.activeEvaluationCountAtStart).max()
      ?? 0
  }

  public var averageCandidateEvaluationDurationSeconds: Double? {
    let durations = candidates.compactMap(\.durationSeconds)
    guard !durations.isEmpty else { return nil }
    return durations.reduce(0, +) / Double(durations.count)
  }

  public var candidateEvaluationCount: Int {
    candidates.count
  }

  public var actualParallelismLabel: String {
    if let batch = latestVectorizedBatch {
      return "\(batch.completedCandidateCount)/\(batch.candidateCount) \(batch.kind.rawValue)"
    }
    guard candidateEvaluationCount > 0 else { return "--" }
    return "\(maxActiveCandidateEvaluations)/\(maxRequestedCandidateConcurrency) active"
  }

  public var latestVectorizedBatch: LearningCampaignVectorizedBatchState? {
    vectorizedBatches.max { lhs, rhs in
      if lhs.generationIndex != rhs.generationIndex {
        return lhs.generationIndex < rhs.generationIndex
      }
      return lhs.artifactPath < rhs.artifactPath
    }
  }

  public var latestAcceleratorDevice: String? {
    latestVectorizedBatch?.acceleratorDevice ?? accelerator?.acceleratorLabel
  }

  public func candidates(
    seed: String,
    generationIndex: Int
  ) -> [LearningCampaignCandidateState] {
    candidates
      .filter { $0.seed == seed && $0.generationIndex == generationIndex }
      .sorted { lhs, rhs in
        let lhsFitness = lhs.scalarFitness ?? -.greatestFiniteMagnitude
        let rhsFitness = rhs.scalarFitness ?? -.greatestFiniteMagnitude
        if lhsFitness != rhsFitness { return lhsFitness > rhsFitness }
        return lhs.candidateID < rhs.candidateID
      }
  }

  public var autonomyStages: [LearningCampaignAutonomyStageState] {
    summary?.autonomousPipelineExecution?.stageRecords.map(LearningCampaignAutonomyStageState.init)
      ?? []
  }

  public var autonomyPipelineSummary: String {
    let stages = autonomyStages
    guard !stages.isEmpty else { return "--" }
    let completed = stages.filter {
      $0.status == AutonomousTrainingStageExecutionStatus.completed.rawValue
    }.count
    let blocked = stages.filter {
      $0.status == AutonomousTrainingStageExecutionStatus.blocked.rawValue
    }.count
    if blocked > 0 {
      return "\(completed)/\(stages.count) completed, \(blocked) blocked"
    }
    return "\(completed)/\(stages.count) completed"
  }

  public var isActive: Bool {
    let label = statusLabel.lowercased()
    return label == "running" || label == "started"
  }

  public var diagnosis: LearningCampaignRunDiagnosis {
    progress.diagnosis
  }

  public var failureReasons: [String] {
    diagnosis.reasons
  }

  public var primaryFailureReason: String? {
    diagnosis.primaryIssue
  }

  public var diagnosticText: String {
    var lines: [String] = [
      "artifactRoot=\(artifactDirectory.path)",
      "status=\(statusLabel)",
      "validation=\(validationLabel)",
      "task=\(task)",
      "trainingStage=\(trainingStageLabel)",
      "trainingStageKind=\(trainingStageKindLabel)",
      "suites=\(suiteSummary)",
      "seeds=\(seedCount)",
      "accepted=\(acceptedCount)",
      "parallelism=\(actualParallelismLabel)",
    ]
    if let latestAcceleratorDevice {
      lines.append("accelerator=\(latestAcceleratorDevice)")
    }
    if let latestVectorizedBatch {
      lines.append("vectorizedExecution=\(latestVectorizedBatch.executionSummary)")
    }
    if !vectorizedBatches.isEmpty {
      lines.append("vectorizedBatches=\(vectorizedBatches.count)")
    }
    if let finalCheckpoint {
      lines.append("finalCheckpoint=\(finalCheckpoint)")
    }
    if let validationReceiptIssue {
      lines.append("validationReceiptIssue=\(validationReceiptIssue)")
    }
    if let strictValidationReceiptIssue {
      lines.append("strictValidationReceiptIssue=\(strictValidationReceiptIssue)")
    }
    if let diagnosticValidationReceiptIssue {
      lines.append("diagnosticValidationReceiptIssue=\(diagnosticValidationReceiptIssue)")
    }
    if let strictValidation {
      lines.append("strictValidatorProfile=\(strictValidation.validator.profileID)")
      lines.append(
        "strictValidatorCapabilities=\(strictValidation.validator.capabilities.map(\.rawValue).joined(separator: ","))"
      )
      if !strictValidation.issues.isEmpty {
        lines.append("recordedStrictValidationIssues:")
        lines.append(contentsOf: strictValidation.issues.map {
          "- \($0.code): \($0.detail)"
        })
      }
    }
    if let diagnosticValidation {
      lines.append("diagnosticValidatorProfile=\(diagnosticValidation.validator.profileID)")
      lines.append(
        "diagnosticValidatorCapabilities=\(diagnosticValidation.validator.capabilities.map(\.rawValue).joined(separator: ","))"
      )
      if !diagnosticValidation.issues.isEmpty {
        lines.append("recordedDiagnosticValidationIssues:")
        lines.append(contentsOf: diagnosticValidation.issues.map {
          "- \($0.code): \($0.detail)"
        })
      }
    }
    if let latestEvent {
      lines.append("latestEvent=\(latestEvent.timestamp) \(latestEvent.event)")
      if let status = latestEvent.status {
        lines.append("latestEventStatus=\(status)")
      }
      if let exitCode = latestEvent.exitCode {
        lines.append("latestEventExitCode=\(exitCode)")
      }
    }
    let reasons = failureReasons
    if !reasons.isEmpty {
      lines.append("failureReasons:")
      lines.append(contentsOf: reasons.map { "- \($0)" })
    }
    return lines.joined(separator: "\n")
  }

  private var episodeMultiplier: Int {
    let episodeCount = plan?.searchEpisodes ?? 1
    let suiteCount = plan?.searchSuites.count ?? 1
    return max(1, episodeCount) * max(1, suiteCount)
  }
}

public struct LearningCampaignRunStore {
  private let artifactReader: any KuyuUITrainingArtifactReading
  private let readLimits: LearningCampaignArtifactReadLimits

  public init(
    artifactReader: any KuyuUITrainingArtifactReading = KuyuUITrainingArtifactReader(),
    readLimits: LearningCampaignArtifactReadLimits? = nil
  ) {
    self.artifactReader = artifactReader
    self.readLimits = readLimits ?? .current
  }

  public func load(from artifactDirectory: URL) throws -> LearningCampaignRunStoreState {
    let artifacts = try LearningCampaignArtifactReader().open(
      artifactRoot: artifactDirectory
    )
    let state = try load(
      from: artifactDirectory,
      progressEvents: decodeJSONLines(
        LearningCampaignProgressEvent.self,
        relativePath: "progress.jsonl",
        reading: artifacts,
        allowsTrailingPartialLine: true
      ),
      reading: artifacts
    )
    try artifacts.verifyRootIdentity()
    return state
  }

  func load(
    from artifactDirectory: URL,
    progressEvents: [LearningCampaignProgressEvent]
  ) throws -> LearningCampaignRunStoreState {
    let artifacts = try LearningCampaignArtifactReader().open(
      artifactRoot: artifactDirectory
    )
    let state = try load(
      from: artifactDirectory,
      progressEvents: progressEvents,
      reading: artifacts
    )
    try artifacts.verifyRootIdentity()
    return state
  }

  private func load(
    from artifactDirectory: URL,
    progressEvents: [LearningCampaignProgressEvent],
    reading artifacts: any LearningCampaignArtifactReading
  ) throws -> LearningCampaignRunStoreState {
    let decodedPlan: LearningCampaignPlan? = try decodeIfPresent(
      LearningCampaignPlan.self,
      relativePath: "learning-campaign-plan.json",
      reading: artifacts
    )
    let evolutionManifest: EvolutionRunManifest? = try decodeIfPresent(
      EvolutionRunManifest.self,
      relativePath: "evolution-manifest.json",
      reading: artifacts
    )
    let plan = decodedPlan
    let decodedStatus: LearningCampaignStatus? = try decodeIfPresent(
      LearningCampaignStatus.self,
      relativePath: "campaign-status.json",
      reading: artifacts
    )
    let status = decodedStatus ?? makeStatusFallback(manifest: evolutionManifest)
    let summary: LearningCampaignSummary? = try decodeIfPresent(
      LearningCampaignSummary.self,
      relativePath: "learning-campaign-summary.json",
      reading: artifacts
    )
    let validationResult = loadValidations(from: artifactDirectory)
    let retention: LearningCampaignArtifactRetentionSummary? = try decodeIfPresent(
      LearningCampaignArtifactRetentionSummary.self,
      relativePath: "artifact-retention.json",
      reading: artifacts
    )

    return LearningCampaignRunStoreState(
      artifactDirectory: artifactDirectory,
      plan: plan,
      status: status,
      summary: summary,
      validation: nil,
      retention: retention ?? summary?.retention,
      accelerator: try decodeIfPresent(
        LearningCampaignAcceleratorSnapshot.self,
        relativePath: "accelerator-snapshot.json",
        reading: artifacts
      ),
      progressEvents: progressEvents,
      generations: try loadGenerations(reading: artifacts),
      candidates: try loadCandidates(reading: artifacts),
      vectorizedBatches: try artifactReader.validatedVectorizedBatches(
        in: artifactDirectory,
        reading: artifacts
      ),
      acceptedCheckpoints: try loadAcceptedCheckpoints(
        from: artifactDirectory,
        reading: artifacts
      ),
      evolutionManifest: evolutionManifest,
      strictValidation: validationResult.strict.receipt,
      diagnosticValidation: validationResult.diagnostic.receipt,
      strictValidationReceiptIssue: validationResult.strict.issue,
      diagnosticValidationReceiptIssue: validationResult.diagnostic.issue
    )
  }

  private func loadValidations(from artifactDirectory: URL) -> (
    strict: (receipt: LearningCampaignValidation?, issue: String?),
    diagnostic: (receipt: LearningCampaignValidation?, issue: String?)
  ) {
    let reader = LearningCampaignValidationReceiptReader()
    return (
      loadValidation(from: artifactDirectory, kind: .strict, reader: reader),
      loadValidation(from: artifactDirectory, kind: .diagnostic, reader: reader)
    )
  }

  private func loadValidation(
    from artifactDirectory: URL,
    kind: LearningCampaignValidationReceiptKind,
    reader: LearningCampaignValidationReceiptReader
  ) -> (receipt: LearningCampaignValidation?, issue: String?) {
    do {
      return (
        try reader.receipt(in: artifactDirectory, kind: kind),
        nil
      )
    } catch {
      return (nil, String(describing: error))
    }
  }

  private func loadAcceptedCheckpoints(
    from artifactDirectory: URL,
    reading artifacts: any LearningCampaignArtifactReading
  ) throws
    -> [LearningCampaignAcceptedCheckpointState]
  {
    var states: [LearningCampaignAcceptedCheckpointState] = []
    if let rootDecision = try loadAcceptedCheckpointDecision(
      seed: "evolution",
      relativeEvolutionPath: "",
      artifactDirectory: artifactDirectory,
      reading: artifacts
    ) {
      states.append(rootDecision)
    }

    for seedDirectoryName in try artifacts.directoryNames(at: "seeds") ?? [] {
      let evolutionPath = "seeds/\(seedDirectoryName)/evolution"
      if let decision = try loadAcceptedCheckpointDecision(
        seed: seedDirectoryName,
        relativeEvolutionPath: evolutionPath,
        artifactDirectory: artifactDirectory,
        reading: artifacts
      ) {
        states.append(decision)
      }
    }
    return states.sorted { lhs, rhs in
      if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
      return lhs.id < rhs.id
    }
  }

  private func loadAcceptedCheckpointDecision(
    seed: String,
    relativeEvolutionPath: String,
    artifactDirectory: URL,
    reading artifacts: any LearningCampaignArtifactReading
  ) throws -> LearningCampaignAcceptedCheckpointState? {
    let decisionPath = joinedPath(
      relativeEvolutionPath,
      EvolutionAcceptedCheckpointDecision.fileName
    )
    guard try artifacts.data(
      at: decisionPath,
      maximumByteCount: readLimits.maximumJSONByteCount
    ) != nil else {
      return nil
    }
    let evolutionDirectory = relativeEvolutionPath.isEmpty
      ? artifactDirectory
      : artifactDirectory.appendingPathComponent(relativeEvolutionPath, isDirectory: true)
    let bundle = try artifactReader.validatedEvolutionArtifacts(
      in: evolutionDirectory,
      reading: artifacts
    )
    return LearningCampaignAcceptedCheckpointState(
      seed: seed,
      decision: bundle.acceptedCheckpoint
    )
  }

  private func loadGenerations(
    reading artifacts: any LearningCampaignArtifactReading
  ) throws
    -> [LearningCampaignGenerationState]
  {
    var states: [LearningCampaignGenerationState] = []
    let rootGenerationRecords = try decodeJSONLines(
      PopulationGenerationRecord.self,
      relativePath: "generations.jsonl",
      reading: artifacts
    )
    if !rootGenerationRecords.isEmpty {
      states.append(
        contentsOf: rootGenerationRecords.map {
          LearningCampaignGenerationState(seed: "evolution", record: $0)
        })
    }
    for seedDirectoryName in try artifacts.directoryNames(at: "seeds") ?? [] {
      let records = try decodeJSONLines(
        PopulationGenerationRecord.self,
        relativePath: "seeds/\(seedDirectoryName)/evolution/generations.jsonl",
        reading: artifacts
      )
      states.append(
        contentsOf: records.map {
          LearningCampaignGenerationState(seed: seedDirectoryName, record: $0)
        })
    }
    return states.sorted { lhs, rhs in
      if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
      return lhs.generationIndex < rhs.generationIndex
    }
  }

  private func loadCandidates(
    reading artifacts: any LearningCampaignArtifactReading
  ) throws
    -> [LearningCampaignCandidateState]
  {
    var states: [LearningCampaignCandidateState] = []
    states.append(
      contentsOf: try loadCandidateStates(
        relativeEvolutionPath: "",
        seed: "evolution",
        reading: artifacts
      ))

    for seedDirectoryName in try artifacts.directoryNames(at: "seeds") ?? [] {
      states.append(
        contentsOf: try loadCandidateStates(
          relativeEvolutionPath: "seeds/\(seedDirectoryName)/evolution",
          seed: seedDirectoryName,
          reading: artifacts
        ))
    }
    return states
  }

  private func loadCandidateStates(
    relativeEvolutionPath: String,
    seed: String,
    reading artifacts: any LearningCampaignArtifactReading
  ) throws -> [LearningCampaignCandidateState] {
    let candidates = try decodeJSONLines(
      GenomeCandidate.self,
      relativePath: joinedPath(relativeEvolutionPath, "candidates.jsonl"),
      reading: artifacts
    )
    guard !candidates.isEmpty else { return [] }
    let fitness = try decodeJSONLines(
      FitnessSummary.self,
      relativePath: joinedPath(relativeEvolutionPath, "fitness.jsonl"),
      reading: artifacts
    )
    let traces = try decodeJSONLines(
      EvolutionCandidateEvaluationTrace.self,
      relativePath: joinedPath(relativeEvolutionPath, "evaluation-trace.jsonl"),
      reading: artifacts
    )
    let fitnessByCandidate = Dictionary(uniqueKeysWithValues: fitness.map { ($0.candidateID, $0) })
    let traceByCandidate = Dictionary(uniqueKeysWithValues: traces.map { ($0.candidateID, $0) })
    return candidates.map { candidate in
      LearningCampaignCandidateState(
        seed: seed,
        candidate: candidate,
        fitness: fitnessByCandidate[candidate.candidateID],
        trace: traceByCandidate[candidate.candidateID]
      )
    }
  }

  private func makeStatusFallback(manifest: EvolutionRunManifest?) -> LearningCampaignStatus? {
    guard let manifest else { return nil }
    return LearningCampaignStatus(
      status: manifest.terminalState.rawValue,
      exitCode: manifest.terminalState == .completed ? 0 : 1,
      startedAt: ISO8601DateFormatter().string(from: manifest.startedAt),
      finishedAt: manifest.completedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
    )
  }

  private func decodeIfPresent<T: Decodable>(
    _ type: T.Type,
    relativePath: String,
    reading artifacts: any LearningCampaignArtifactReading
  ) throws -> T? {
    guard let data = try artifacts.data(
      at: relativePath,
      maximumByteCount: readLimits.maximumJSONByteCount
    ) else {
      return nil
    }
    return try decoder.decode(type, from: data)
  }

  private func decodeJSONLines<T: Decodable>(
    _ type: T.Type,
    relativePath: String,
    reading artifacts: any LearningCampaignArtifactReading,
    allowsTrailingPartialLine: Bool = false
  ) throws -> [T] {
    guard let data = try artifacts.data(
      at: relativePath,
      maximumByteCount: readLimits.maximumJSONLinesByteCount
    ) else {
      return []
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw LearningCampaignArtifactReadError.unsafeEntry(relativePath)
    }
    let rawLines = text.split(whereSeparator: \.isNewline)
    var records: [T] = []
    for (index, line) in rawLines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let data = Data(trimmed.utf8)
      do {
        records.append(try decoder.decode(type, from: data))
      } catch {
        let isLastLine = index == rawLines.index(before: rawLines.endIndex)
        if allowsTrailingPartialLine && isLastLine && !text.hasSuffix("\n") {
          continue
        }
        throw error
      }
    }
    return records
  }

  private func joinedPath(_ directory: String, _ file: String) -> String {
    directory.isEmpty ? file : "\(directory)/\(file)"
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
      positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity",
      nan: "NaN"
    )
    return decoder
  }
}
