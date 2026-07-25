import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuTraining
import KuyuUI

struct EvaluateCheckpoint: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "evaluate-checkpoint",
    abstract:
      "Evaluate one checkpoint against graded A1 suites directly, without campaign preflight, mutation, or acceptance-stage re-evaluation. Read-only diagnostic; promotion stays owned by run-learning-campaign."
  )

  @Option(name: .customLong("checkpoint"), help: "Checkpoint directory to evaluate.")
  var checkpoint: String

  @Option(help: "Task to evaluate.")
  var task: LearningCampaignTask = .attitude

  @Option(help: "Determinism tier: tier0, tier1, tier2.")
  var tier: TierChoice = .tier1

  @Option(help: "Comma-separated A1 suite IDs.")
  var suites: String = "0,2,3"

  @Option(help: "Graded episodes per suite.")
  var episodes: Int = 3

  @Option(name: .customLong("stress-severity"), help: "Graded stress severity in [0, 1].")
  var stressSeverity: Double = 1.0

  @Option(help: "Robot manifest path.")
  var model: String = KuyuUIModelPaths.defaultRobotManifestPath()

  @Option(help: "Rollout worker count.")
  var workers: Int = 3

  @Option(
    name: .customLong("world-execution"),
    help: "World execution: auto, accelerated, cpu.")
  var worldExecution: LearningCampaignWorldExecution = .auto

  @Option(name: .customLong("cut-period-steps"), help: "Controller cut period in physics steps.")
  var cutPeriodSteps: UInt64 = 2

  @Option(name: .customLong("artifact-dir"), help: "Directory for the vectorized evaluation artifact.")
  var artifactDir: String?

  enum ArgumentError: Error {
    case invalidSuiteList(String)
  }

  mutating func run() async throws {
    let suiteIDs = try suites.split(separator: ",").map { piece -> Int in
      guard let value = Int(piece.trimmingCharacters(in: .whitespaces)), value >= 0 else {
        throw ArgumentError.invalidSuiteList(suites)
      }
      return value
    }
    guard !suiteIDs.isEmpty else {
      throw ArgumentError.invalidSuiteList(suites)
    }
    let checkpointURL = URL(fileURLWithPath: checkpoint, isDirectory: true).standardizedFileURL
    let artifactDirectory =
      artifactDir.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
      ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-evaluate-checkpoint", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: artifactDirectory,
      withIntermediateDirectories: true
    )
    let evaluator = ReferenceQuadrotorCheckpointSuiteEvaluator(
      task: task.rolloutTask,
      tier: learningCampaignTier(from: tier),
      cutPeriodSteps: cutPeriodSteps,
      suites: suiteIDs,
      episodes: episodes,
      workers: workers,
      robotManifestPath: KuyuUIModelPaths.resolveRobotManifestPath(model),
      stressSeverity: stressSeverity,
      worldExecutionRequirement: worldExecution.requirement(task: task)
    )
    let wallStart = Date()
    let evaluation = try await evaluator.evaluate(
      checkpointURL: checkpointURL,
      artifactDirectory: artifactDirectory
    )
    let wallSeconds = Date().timeIntervalSince(wallStart)

    print("[evaluate-checkpoint] checkpoint=\(checkpointURL.path)")
    print(
      "[evaluate-checkpoint] task=\(task.rawValue) suites=\(suites) episodes=\(episodes) severity=\(stressSeverity)"
    )
    var passedCount = 0
    for quality in evaluation.taskQuality {
      let verdict = quality.passed ? "PASS" : "FAIL"
      if quality.passed { passedCount += 1 }
      let reasons = quality.failureReasons.isEmpty
        ? ""
        : " reasons=\(quality.failureReasons.joined(separator: ","))"
      print(
        "[evaluate-checkpoint] \(verdict) \(quality.scenarioID) seed=\(quality.seed)\(reasons)"
      )
    }
    print(
      "[evaluate-checkpoint] passed=\(passedCount)/\(evaluation.taskQuality.count) fitness=\(evaluation.fitness.scalarFitness) rewardAverage=\(evaluation.fitness.rewardAverage) taskPassRate=\(evaluation.fitness.taskPassRate)"
    )
    if let artifactURL = evaluation.vectorizedArtifactURL {
      print("[evaluate-checkpoint] artifact=\(artifactURL.path)")
    }
    print(String(format: "[evaluate-checkpoint] wallSeconds=%.1f", wallSeconds))
  }
}
