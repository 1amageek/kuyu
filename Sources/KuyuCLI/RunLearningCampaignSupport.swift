import ArgumentParser
import Darwin
import Foundation
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuTraining

nonisolated(unsafe) private var learningCampaignStopSignalRequested: sig_atomic_t = 0

private func requestLearningCampaignStop(_ signal: Int32) {
  if learningCampaignStopSignalRequested != 0 {
    _exit(128 + signal)
  }
  learningCampaignStopSignalRequested = signal
}

struct LearningCampaignConsoleReporter: Sendable {
  func report(_ event: TrainingRunEvent) -> TrainingRunResultTerminalClassifier.Classification? {
    switch event {
    case .progress(let progress):
      print(formattedProgress(progress))
      return nil
    case .log(let log):
      let seed = log.seed.map { " seed=\($0)" } ?? ""
      let generation = log.generationIndex.map { " generation=\($0)" } ?? ""
      let candidate = log.candidateID.map { " candidate=\($0)" } ?? ""
      let progress = log.progressFraction.map { String(format: " progress=%.1f%%", $0 * 100) } ?? ""
      let metadata = log.metadata
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: " ")
      let suffix = metadata.isEmpty ? "" : " \(metadata)"
      print(
        "[learning-campaign] \(log.level.rawValue) phase=\(log.phase)\(seed)\(generation)\(candidate)\(progress) message=\"\(log.message)\"\(suffix)"
      )
      return nil
    case .started(let manifest):
      print("[learning-campaign] started runID=\(manifest.runID)")
      return nil
    case .iterationStarted(let iteration):
      print("[learning-campaign] iteration started iteration=\(iteration)")
      return nil
    case .suiteCompleted(let iteration, _, let score):
      print("[learning-campaign] suite completed iteration=\(iteration) score=\(score)")
      return nil
    case .datasetExported(let iteration, let directory, let count):
      print(
        "[learning-campaign] dataset exported iteration=\(iteration) count=\(count) directory=\(directory)"
      )
      return nil
    case .trainingCompleted(let iteration, let result):
      print(
        "[learning-campaign] training completed iteration=\(iteration) loss=\(result.finalLoss)")
      return nil
    case .reinforcementTrainingCompleted(let iteration, let result):
      print(
        "[learning-campaign] reinforcement completed iteration=\(iteration) reward=\(result.rewardAverage)"
      )
      return nil
    case .convergenceUpdated(let summary):
      print("[learning-campaign] convergence accepted=\(summary.accepted) reason=\(summary.reason)")
      return nil
    case .completed(let result):
      let classification = TrainingRunResultTerminalClassifier().classify(result: result)
      print(
        "[learning-campaign] completed terminalState=\(result.manifest.terminalState.rawValue) checkpointDecision=\(result.checkpointDecision.state.rawValue) terminalAcceptance=\(classification.status.rawValue) reason=\(classification.reason)"
      )
      return classification
    }
  }

  func formattedProgress(_ progress: TrainingRunProgressEvent) -> String {
    var fields = [
      "event=\(progress.event)",
    ]
    append("status", progress.status, to: &fields)

    if let work = progress.workProgress {
      fields.append("phase=\(work.phase.rawValue)")
      fields.append("state=\(work.state.rawValue)")
      fields.append("runID=\(work.scope.runID)")
      append("iteration", work.scope.iterationIndex, to: &fields)
      append("generation", work.scope.generationIndex, to: &fields)
      append("candidate", work.scope.candidateID, to: &fields)
      append("batchID", work.scope.batchID, to: &fields)
      if let batchIndex = work.scope.batchIndex, let batchCount = work.scope.batchCount {
        fields.append("batch=\(batchIndex + 1)/\(batchCount)")
      }
      fields.append("unit=\(work.unit.kind.rawValue)")
      fields.append("unitID=\(work.unit.identifier)")
      append("suite", work.unit.suiteIndex, to: &fields)
      append("scenario", work.unit.scenarioID, to: &fields)
      append("scenarioSeed", work.unit.scenarioSeed, to: &fields)
      fields.append("completed=\(work.completedUnitCount)")
      fields.append("total=\(work.totalUnitCount)")
      fields.append(String(format: "progress=%.1f%%", work.fractionCompleted * 100))
      append("population", work.populationSize, to: &fields)
    } else {
      append("phase", progress.phase, to: &fields)
      append("seed", progress.seed, to: &fields)
      append("generation", progress.generationIndex, to: &fields)
      append("candidate", progress.candidateID, to: &fields)
      if let fraction = progress.progressFraction {
        fields.append(String(format: "progress=%.1f%%", fraction * 100))
      }
    }

    appendMetric("fitness", progress.fitness, to: &fields)
    appendMetric("rewardAverage", progress.rewardAverage, to: &fields)
    appendMetric("taskPassRate", progress.taskPassRate, to: &fields)
    appendMetric("safetyViolationRate", progress.safetyViolationRate, to: &fields)
    appendMetric("workerThroughput", progress.workerThroughput, to: &fields)
    append("gpuAcceleration", progress.gpuAcceleration, to: &fields)
    append("tensorWorldBatch", progress.tensorWorldBatch, to: &fields)
    append("populationSize", progress.vectorizedPopulationSize, to: &fields)
    append("worldCount", progress.vectorizedWorldCount, to: &fields)
    append("message", progress.message?.debugDescription, to: &fields)
    if !progress.failureReasons.isEmpty {
      fields.append("failures=\(progress.failureReasons.joined(separator: ", ").debugDescription)")
    }
    append("path", progress.path?.debugDescription, to: &fields)
    return "[learning-campaign] progress " + fields.joined(separator: " ")
  }

  private func append<T>(_ name: String, _ value: T?, to fields: inout [String]) {
    guard let value else { return }
    fields.append("\(name)=\(value)")
  }

  private func appendMetric(_ name: String, _ value: Double?, to fields: inout [String]) {
    guard let value else { return }
    fields.append("\(name)=\(String(format: "%.6g", value))")
  }
}

extension RunLearningCampaign {
  static func installStopSignalHandlers(
    onStopRequested: @escaping @Sendable (LearningCampaignProcessSignal) async -> Void
  ) -> Task<Void, Never> {
    learningCampaignStopSignalRequested = 0
    signal(SIGINT, requestLearningCampaignStop)
    signal(SIGTERM, requestLearningCampaignStop)

    return Task {
      while !Task.isCancelled {
        if learningCampaignStopSignalRequested != 0 {
          guard
            let signal = LearningCampaignProcessSignal(
              number: learningCampaignStopSignalRequested
            )
          else {
            _exit(ExitCode.failure.rawValue)
          }
          print(
            "\n[learning-campaign] \(signal.label) received - cancelling active work and preserving durable artifacts."
          )
          await onStopRequested(signal)
          return
        }
        do {
          try await Task.sleep(for: .milliseconds(100))
        } catch {
          return
        }
      }
    }
  }

  static func restoreStopSignalHandlers() {
    signal(SIGINT, SIG_DFL)
    signal(SIGTERM, SIG_DFL)
    learningCampaignStopSignalRequested = 0
  }

  func parseCampaignSeeds(_ raw: String) throws -> [String] {
    let values =
      raw
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !values.isEmpty else {
      throw ValidationError("--seeds must include at least one seed.")
    }
    var seenSeeds = Set<String>()
    var parsedSeeds: [String] = []
    for value in values {
      guard let seed = UInt64(value) else {
        throw ValidationError("--seeds contains an invalid unsigned integer seed: \(value)")
      }
      let canonicalValue = String(seed)
      guard seenSeeds.insert(canonicalValue).inserted else {
        throw ValidationError("--seeds contains a duplicate seed: \(canonicalValue)")
      }
      parsedSeeds.append(canonicalValue)
    }
    return parsedSeeds
  }

  func printTrainingRunEvent(_ event: TrainingRunEvent) -> TrainingRunResultTerminalClassifier
    .Classification?
  {
    LearningCampaignConsoleReporter().report(event)
  }
}

extension TrainingDeterminismTier {
  init(cliTier: LearningCampaignTier) {
    switch cliTier {
    case .tier0:
      self = .tier0
    case .tier1:
      self = .tier1
    case .tier2:
      self = .tier2
    }
  }
}

extension TrainingVariationKind {
  init(cliVariation: LearningCampaignVariation) {
    switch cliVariation {
    case .copy:
      self = .copy
    case .gaussian:
      self = .gaussian
    }
  }
}

extension TrainingArtifactRetentionKind {
  init(cliRetention: LearningCampaignArtifactRetentionMode) {
    switch cliRetention {
    case .compact:
      self = .compact
    case .full:
      self = .full
    }
  }
}
