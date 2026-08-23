import ArgumentParser
import Foundation
import KuyuCore
import KuyuMojoTrainingRuntime
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingApplication
import KuyuTrainingContracts

@main
struct KuyuCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "kuyu",
    abstract: "Run Kuyu simulations and Mojo learning updates.",
    subcommands: [Simulate.self, Train.self]
  )
}

private struct Simulate: AsyncParsableCommand {
  enum BaselineController: String, ExpressibleByArgument {
    case sensor
    case teacher
  }

  static let configuration = CommandConfiguration(
    abstract: "Run deterministic reference-quadrotor scenarios."
  )

  @Option(help: "Baseline controller: sensor or teacher.")
  var controller = BaselineController.teacher

  @Option(help: "Number of canonical attitude scenarios to execute.")
  var scenarioLimit = 1

  @Flag(help: "Run and compare a second deterministic replay.")
  var replayVerification = false

  mutating func run() async throws {
    let allDefinitions = try KuyAtt1Suite().scenarios()
    guard scenarioLimit > 0, scenarioLimit <= allDefinitions.count else {
      throw ValidationError(
        "--scenario-limit must be within 1...\(allDefinitions.count)"
      )
    }
    let gains = try ImuRateDampingCutGains(
      kp: 2,
      kd: 0.25,
      yawDamping: 0.2
    )
    let runner: KuyAtt1Runner
    switch controller {
    case .sensor:
      runner = KuyAtt1Runner(
        schedule: try SimulationSchedule.baseline(cutPeriodSteps: 2),
        determinism: .tier1Baseline,
        gains: gains,
        baselineMode: .sensor,
        replayVerification: replayVerification
      )
    case .teacher:
      runner = try KuyAtt1Runner.activeAltitudeHoldTeacher(
        gains: gains,
        replayVerification: replayVerification
      )
    }
    let output = try await runner.runWithLogs(
      definitions: Array(allDefinitions.prefix(scenarioLimit))
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(output.summary)
    data.append(0x0A)
    try FileHandle.standardOutput.write(contentsOf: data)
  }
}

private struct Train: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Run one validated local learning update."
  )

  @Option(help: "Stable run identifier.")
  var runID = "local-update"

  @Option(help: "Absolute KuyuDataset v7 directory path.")
  var dataset: String

  @Option(help: "Source Manas model bundle identifier.")
  var sourceBundleID: String

  @Option(help: "Absolute source Manas model bundle directory path.")
  var sourceBundle: String

  @Option(help: "Candidate Manas model bundle identifier.")
  var candidateBundleID: String

  @Option(help: "Absolute output directory for the candidate bundle.")
  var candidateBundle: String

  @Option(help: "Hidden width for reward and cost critics.")
  var criticHiddenSize = 128

  @Option(help: "PPO epoch count.")
  var epochs = 4

  @Option(help: "PPO minibatch size.")
  var minibatchSize = 256

  @Option(help: "Adam learning rate.")
  var learningRate: Float = 3.0e-4

  @Option(help: "Maximum transitions loaded from the dataset.")
  var maximumTransitions: UInt64 = 256

  @Option(help: "Maximum scalar values materialized by the adapter.")
  var maximumScalars = 8_000_000

  mutating func run() async throws {
    let request = try FileSystemLearningUpdateRequestFactory().request(
      runID: runID,
      datasetPath: dataset,
      sourceBundleID: sourceBundleID,
      sourceBundlePath: sourceBundle,
      candidateBundleID: candidateBundleID,
      candidateBundlePath: candidateBundle,
      plan: LearningUpdatePlan(
        criticHiddenSize: criticHiddenSize,
        epochCount: epochs,
        minibatchSize: minibatchSize,
        optimizerLearningRate: learningRate,
        maximumTransitions: maximumTransitions,
        maximumScalars: maximumScalars
      )
    )
    let result = try await LearningUpdateCoordinator(
      executor: KuyuMojoLearningUpdateExecutor()
    ).execute(request)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var output = try encoder.encode(result)
    output.append(0x0A)
    try FileHandle.standardOutput.write(contentsOf: output)
  }
}
