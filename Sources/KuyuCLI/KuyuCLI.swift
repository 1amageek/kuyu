import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuPhysics
import KuyuScenarios
import KuyuTraining
import KuyuUI
import ManasCore

@main
struct KuyuCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "kuyu",
    abstract: "Kuyu training world command-line interface.",
    subcommands: [
      Run.self, Rollout.self, Loop.self, Train.self, Runs.self, Control.self, ProbeRoArmM1.self,
      TrainRoArmM1JointTargets.self, PublishRoArmM1HardwareCalibration.self,
      CaptureRoArmM1HardwareRuntime.self, PublishRoArmM1HardwareRuntime.self, ProbeManas.self,
      ProbeManasSuite.self, ProbeCTBRPolicy.self, ProbeCTBRPPOBackend.self, ProbeCTBRRollout.self,
      WriteCTBRCheckpoint.self, BehaviorCloneCTBR.self, DaggerRelabelCTBR.self, TrainManasCore.self,
      MixTrainingDatasets.self, EvaluateManasCheckpoint.self, RunFoundationAcceptance.self,
      BenchmarkReferenceAttitudeM2.self, CalibrateManasCheckpoint.self,
      SelectManasBiasCalibration.self, CheckEnvironments.self, CheckTrainingHarness.self,
      CheckTrainingHarnessSweep.self, CheckKuyuRegression.self, CheckKuyuRegressionMatrix.self,
      EvolveManas.self, RunLearningCampaign.self, RunLearningCampaignWorker.self,
      ValidateLearningCampaign.self, DiagnoseLearningCampaign.self, TrainWorldModel.self,
      ImagineTrain.self,
      PublishWorldModelFusedEvidence.self, Verify.self, Conformance.self, Doctor.self,
    ]
  )
}

enum TierChoice: String, CaseIterable, ExpressibleByArgument {
  case tier0
  case tier1
  case tier2
}

enum ControllerChoice: String, CaseIterable, ExpressibleByArgument {
  case activeAltitudeHold
  case sensorBaseline
  case manasMLX
}

enum RolloutTaskChoice: String, CaseIterable, ExpressibleByArgument {
  case attitude
  case lift
  case singleLift
}

enum CTBRCheckpointTaskChoice: String, CaseIterable, ExpressibleByArgument {
  case attitude
  case lift
}

enum LearningCampaignTaskChoice: String, CaseIterable, ExpressibleByArgument {
  case lift
  case singleLift

  var rolloutTask: RolloutTaskChoice {
    switch self {
    case .lift:
      return .lift
    case .singleLift:
      return .singleLift
    }
  }
}

extension LearningCampaignArtifactRetentionMode: @retroactive ExpressibleByArgument {}
extension LearningCampaignTask: @retroactive ExpressibleByArgument {}
extension LearningCampaignTier: @retroactive ExpressibleByArgument {}
extension LearningCampaignVariation: @retroactive ExpressibleByArgument {}
extension AutonomousOperationDomain: @retroactive ExpressibleByArgument {}
extension EvolutionSearchStrategy: @retroactive ExpressibleByArgument {}
extension ReadinessLevel: @retroactive ExpressibleByArgument {}

struct Run: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Run a single KUY-ATT-1 suite.")

  @Option(help: "Controller to use: activeAltitudeHold, sensorBaseline, or manasMLX.")
  var controller: ControllerChoice = .activeAltitudeHold

  @Option(help: "Determinism tier: tier0, tier1, tier2.")
  var tier: TierChoice = .tier1

  @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
  var cutPeriodSteps: UInt64 = 2

  @Option(help: "Robot manifest path (optional).")
  var model: String = ""

  @Option(help: "World model path override (optional).")
  var world: String = ""

  @Option(help: "Required readiness level.")
  var readiness: ReadinessLevel = .dynamicSimulation

  @Option(help: "kp gain for baseline controller.")
  var kp: Double = 2.0

  @Option(help: "kd gain for baseline controller.")
  var kd: Double = 0.25

  @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
  var yawDamping: Double = 0.2

  @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
  var hoverScale: Double = 1.0

  @Option(
    name: .customLong("descending"),
    help: "Optional descending channels as comma-separated values (e.g. 0.8,0.0,-0.2).")
  var descending: String = ""

  @Option(
    name: .customLong("descending-program"),
    help:
      "Optional descending program as 'time:values;time:values' (e.g. 0:0.4,0,0,0;1.0:0.6,0,0,0).")
  var descendingProgram: String = ""

  @Flag(name: .customLong("no-aux"), help: "Disable aux prediction loss for MLX.")
  var noAux: Bool = false

  @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
  var noQualityGate: Bool = false

  @Option(name: .customLong("export-logs"), help: "Directory to export logs.")
  var exportLogsPath: String?

  @Option(name: .customLong("export-dataset"), help: "Directory to export training dataset.")
  var exportDatasetPath: String?

  @Flag(help: "Exit with non-zero code when the suite fails.")
  var failOnError: Bool = false

  @MainActor
  mutating func run() async throws {
    let determinism = try makeDeterminism(tier: tier)
    let gains = try ImuRateDampingCutGains(
      kp: kp,
      kd: kd,
      yawDamping: yawDamping,
      hoverThrustScale: hoverScale
    )
    let descendingVector = try parseDescendingVector(descending)
    let parsedDescendingProgram = try parseDescendingProgram(descendingProgram)
    if descendingVector != nil, parsedDescendingProgram != nil {
      throw ValidationError("Specify either --descending or --descending-program, not both.")
    }

    let request = SimulationRunRequest(
      controller: controllerSelection(from: controller),
      gains: gains,
      cutPeriodSteps: cutPeriodSteps,
      noise: .zero,
      determinism: determinism,
      robotManifestPath: model,
      worldModelPath: world,
      readinessRequirement: readiness,
      overrideParameters: nil,
      useAux: !noAux,
      useQualityGating: !noQualityGate,
      descendingVector: descendingVector,
      descendingProgram: parsedDescendingProgram
    )
    let output = try await SimulationRunnerService(modelStore: ManasMLXModelStore()).run(
      request: request)

    printSummary(output: output)

    if let exportLogsPath {
      let dir = URL(fileURLWithPath: exportLogsPath, isDirectory: true)
      _ = try KuyAtt1LogWriter().write(output: output, to: dir)
      print("[logs] exported to \(dir.path)")
    }

    if let exportDatasetPath {
      let dir = URL(fileURLWithPath: exportDatasetPath, isDirectory: true)
      let outputs = try TrainingDatasetExporter().write(output: output, to: dir)
      print("[dataset] exported \(outputs.count) scenarios to \(dir.path)")
    }

    if failOnError && !output.summary.suitePassed {
      throw ExitCode.failure
    }
  }
}

struct ProbeCTBRPolicy: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "probe-ctbr-policy",
    abstract: "Run a strict GPU probe for the temporal CTBR actor-critic backend."
  )

  @Option(name: .customLong("batch-size"), help: "Synthetic batch size for the GPU probe.")
  var batchSize: Int = 32

  @Option(name: .customLong("hidden-size"), help: "Actor-critic hidden size.")
  var hiddenSize: Int = 128

  @Option(name: .customLong("epochs"), help: "Training epochs for BC and PPO smoke updates.")
  var epochs: Int = 1

  @Option(help: "Deterministic random seed for synthetic tensor inputs.")
  var seed: UInt64 = 42

  func run() throws {
    let report = try ManasMLXTemporalPolicyProbe().run(
      batchSize: batchSize,
      hiddenSize: hiddenSize,
      epochCount: epochs,
      seed: seed
    )

    print("ctbrPolicyProbe=true")
    print("device=gpu")
    print("batchSize=\(report.batchSize)")
    print("historyLength=\(report.historyLength)")
    print("observationDimension=\(report.observationDimension)")
    print("privilegedDimension=\(report.privilegedDimension)")
    print("hiddenSize=\(report.hiddenSize)")
    print("behaviorCloningActorLoss=\(String(format: "%.6f", report.behaviorCloningActorLoss))")
    print("behaviorCloningCriticLoss=\(String(format: "%.6f", report.behaviorCloningCriticLoss))")
    print("ppoActorLoss=\(String(format: "%.6f", report.ppoActorLoss))")
    print("ppoCriticLoss=\(String(format: "%.6f", report.ppoCriticLoss))")
  }
}

struct ProbeCTBRPPOBackend: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "probe-ctbr-ppo-backend",
    abstract:
      "Run the strict CTBR rollout dataset loader and MLX PPO backend, then save a trained Manas bundle."
  )

  enum ProbeError: Error, CustomStringConvertible {
    case outputAlreadyExists(String)
    case invalidCandidateCount(Int)
    case invalidDuration(Double)

    var description: String {
      switch self {
      case .outputAlreadyExists(let path):
        return "output-already-exists: \(path)"
      case .invalidCandidateCount(let count):
        return "invalid-candidate-count: \(count)"
      case .invalidDuration(let duration):
        return "invalid-duration: \(duration)"
      }
    }
  }

  @Option(
    name: .customLong("artifact-root"),
    help: "Destination artifact root. Defaults to a temporary directory.")
  var artifactRoot: String = ""

  @Option(
    name: .customLong("candidates"),
    help: "Number of CTBR candidates to roll out together on the tensor world.")
  var candidateCount: Int = 8

  @Option(name: .customLong("duration"), help: "Tensor-world rollout duration in seconds.")
  var duration: Double = 1.0

  @Option(name: .customLong("epochs"), help: "PPO update epochs.")
  var epochs: Int = 1

  @Option(name: .customLong("hidden-size"), help: "Temporal actor-critic hidden size.")
  var hiddenSize: Int = 128

  func run() async throws {
    guard candidateCount > 0 else {
      throw ProbeError.invalidCandidateCount(candidateCount)
    }
    guard duration.isFinite, duration > 0 else {
      throw ProbeError.invalidDuration(duration)
    }

    let root =
      artifactRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kuyu-ctbr-ppo-backend-\(UUID().uuidString)", isDirectory: true)
      : URL(fileURLWithPath: artifactRoot).standardizedFileURL
    if FileManager.default.fileExists(atPath: root.path) {
      throw ProbeError.outputAlreadyExists(root.path)
    }
    try MLXRuntimeReadinessService().check()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let sourceCheckpointURL = root.appendingPathComponent("source.manasbundle", isDirectory: true)
    let starterContract = ReferenceQuadrotorStarterCheckpointContractService()
      .defaultContract(for: .lift)
    let policyContract = ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract()
    let sourceManifest = try ManasMLXTemporalCheckpointWriter().write(
      request: ManasMLXTemporalCheckpointWriteRequest(
        checkpointURL: sourceCheckpointURL,
        name: "CTBR PPO Probe Source",
        policyContract: policyContract,
        observationContract: ReferenceQuadrotorLearningContracts.temporalCTBRObservationContract(),
        actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
        embodiment: nil,
        hiddenSize: hiddenSize,
        initializationSeed: starterContract.initializationSeed
      )
    )

    let datasetURL = root.appendingPathComponent("tensor-world-rollouts", isDirectory: true)
    let rolloutReport = try await ManasMLXReferenceQuadrotorRolloutDatasetExporter().export(
      sourceCheckpointURL: sourceCheckpointURL,
      outputURL: datasetURL,
      candidateCount: candidateCount,
      duration: duration,
      suite: 6
    )

    let checkpointRoot = root.appendingPathComponent("checkpoints", isDirectory: true)
    let backend = await ManasMLXTrainingBackend(
      runtime: ManasMLXTrainingRuntime(modelStore: ManasMLXModelStore()),
      saveDirectory: checkpointRoot,
      rolloutDatasetLoader: ReferenceQuadrotorTemporalRolloutDatasetLoaderFactory.make()
    )
    let result = try await backend.trainReinforcement(
      request: ReinforcementTrainingBackendRequest(
        rolloutDatasetURL: datasetURL,
        sourceSnapshot: TrainingBackendSnapshot(
          snapshotID: "ctbr-ppo-probe-source",
          checkpointID: sourceManifest.name,
          checkpointURL: sourceCheckpointURL,
          robotManifestID: nil,
          configHash: "ctbr-ppo-probe"
        ),
        workerCount: 1,
        iterations: epochs,
        learningRate: 3e-4,
        algorithm: .actorCritic,
        maxBatches: nil,
        workerPlan: nil
      )
    )

    if let checkpointURL = result.candidateCheckpointURL {
      _ = try ManasMLXTemporalCheckpointReadinessService().report(
        for: ManasMLXTemporalCheckpointReadinessRequest(checkpointURL: checkpointURL)
      )
    }

    print("ctbrPPOBackendProbe=true")
    print("device=gpu")
    print("artifactRoot=\(root.path)")
    print("rolloutDataset=\(datasetURL.path)")
    print("rolloutEpisodes=\(rolloutReport.episodeCount)")
    print("rolloutRewardAverage=\(String(format: "%.6f", rolloutReport.rewardAverage))")
    print("rolloutMinimumStepCount=\(rolloutReport.minimumStepCount)")
    print("rolloutMaximumStepCount=\(rolloutReport.maximumStepCount)")
    print("tensorWorldUsed=\(rolloutReport.tensorWorldUsed)")
    print("candidateCount=\(rolloutReport.candidateCount)")
    print("sourceCheckpoint=\(sourceCheckpointURL.path)")
    print("candidateCheckpointID=\(result.candidateCheckpointID ?? "n/a")")
    print("candidateCheckpoint=\(result.candidateCheckpointURL?.path ?? "n/a")")
    print("rewardAverage=\(String(format: "%.6f", result.rewardAverage))")
    let finalLoss = result.finalLoss ?? Double.nan
    print("finalLoss=\(String(format: "%.6f", finalLoss))")
    print("workerCount=\(result.workerMetrics.count)")
  }
}

struct ProbeCTBRRollout: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "probe-ctbr-rollout",
    abstract: "Run a GPU tensor-world rollout probe with temporal CTBR policy bundles."
  )

  @Option(
    name: .customLong("candidates"), help: "Number of CTBR policy candidates to roll out together.")
  var candidateCount: Int = 8

  func run() async throws {
    let report = try await ManasMLXReferenceQuadrotorRolloutProbe().run(
      candidateCount: candidateCount
    )
    print("ctbrRolloutProbe=true")
    print("device=\(report.device)")
    print("policyFamily=\(report.policyFamily)")
    print("actionEncoding=\(report.actionEncoding.rawValue)")
    print("candidateCount=\(report.candidateCount)")
    print("episodeCount=\(report.episodeCount)")
    print("historyLength=\(report.historyLength)")
    print("observationDimension=\(report.observationDimension)")
    print("rewardAverage=\(String(format: "%.6f", report.rewardAverage))")
    print("minimumStepCount=\(report.minimumStepCount)")
    print("maximumStepCount=\(report.maximumStepCount)")
    print("tensorWorldUsed=\(report.tensorWorldUsed)")
  }
}

struct BehaviorCloneCTBR: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "behavior-clone-ctbr",
    abstract:
      "Behavior-clone a temporal CTBR policy from an active altitude hold rollout dataset to seed a stabilization prior before RL/GA."
  )

  @Option(
    name: .customLong("source-checkpoint"),
    help: "Source CTBR .manasbundle providing the policy architecture (obs/history/action dims).")
  var sourceCheckpoint: String = ""

  @Option(
    name: .customLong("rollout-dataset"),
    help: "Teacher rollout dataset directory (from `rollout --export-dataset`).")
  var rolloutDataset: String = ""

  @Option(
    name: .customLong("output"),
    help: "Destination .manasbundle for the behavior-cloned checkpoint.")
  var output: String = ""

  @Option(name: .customLong("epochs"), help: "Behavior-cloning epochs.")
  var epochs: Int = 50

  @Option(
    name: .customLong("actor-lr"),
    help:
      "Actor learning rate for behavior cloning (the policy config's 3e-4 is too small for supervised BC)."
  )
  var actorLearningRate: Double = 0.001

  @Option(name: .customLong("name"), help: "Bundle display name.")
  var name: String = "Attitude CTBR BC"

  func run() throws {
    let trimmedSource = sourceCheckpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedDataset = rolloutDataset.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSource.isEmpty else { throw ValidationError("--source-checkpoint is required.") }
    guard !trimmedDataset.isEmpty else { throw ValidationError("--rollout-dataset is required.") }
    guard !trimmedOutput.isEmpty else { throw ValidationError("--output is required.") }
    let outputURL = URL(fileURLWithPath: trimmedOutput, isDirectory: true)
    guard outputURL.pathExtension == "manasbundle" else {
      throw ValidationError("--output must be a .manasbundle directory.")
    }
    guard epochs > 0 else { throw ValidationError("--epochs must be > 0.") }
    guard actorLearningRate.isFinite, actorLearningRate > 0 else {
      throw ValidationError("--actor-lr must be > 0.")
    }
    let result = try ManasMLXTemporalReinforcementWarmupService(
      rolloutDatasetLoader: ReferenceQuadrotorTemporalRolloutDatasetLoaderFactory.make()
    ).behaviorClone(
      sourceCheckpointURL: URL(fileURLWithPath: trimmedSource, isDirectory: true),
      rolloutDatasetURL: URL(fileURLWithPath: trimmedDataset, isDirectory: true),
      epochCount: epochs,
      actorLearningRate: Float(actorLearningRate),
      outputCheckpointURL: outputURL,
      checkpointName: name
    )
    print("behaviorCloneCTBR=true")
    print("output=\(outputURL.path)")
    print("epochs=\(epochs)")
    print("finalActorLoss=\(result.actorLosses.last ?? .nan)")
    print("finalCriticLoss=\(result.criticLosses.last ?? .nan)")
  }
}

struct DaggerRelabelCTBR: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "dagger-relabel-ctbr",
    abstract:
      "Roll a CTBR attitude policy through the A1 scenarios and write a teacher-relabeled (DAgger) dataset covering the policy's visited states."
  )

  @Option(help: "Task suite (attitude only).")
  var task: RolloutTaskChoice = .attitude

  @Option(help: "Determinism tier: tier0, tier1, tier2.")
  var tier: TierChoice = .tier0

  @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
  var cutPeriodSteps: UInt64 = 2

  @Option(help: "Robot manifest path.")
  var model: String = ""

  @Option(name: .customLong("checkpoint"), help: "CTBR policy checkpoint to roll out.")
  var checkpointPath: String

  @Option(
    name: .customLong("output"), help: "Directory where the teacher-relabeled dataset is written.")
  var outputPath: String

  @Option(help: "kp gain for teacher baseline.")
  var kp: Double = 2.0

  @Option(help: "kd gain for teacher baseline.")
  var kd: Double = 0.25

  @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for teacher baseline.")
  var yawDamping: Double = 0.2

  @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
  var hoverScale: Double = 1.0

  @Flag(
    name: .customLong("include-successful"),
    help: "Relabel all scenarios, not only the policy's failed ones (broader coverage).")
  var includeSuccessful: Bool = false

  @MainActor
  mutating func run() async throws {
    guard task == .attitude else {
      throw ValidationError("dagger-relabel-ctbr currently supports --task attitude only.")
    }
    let checkpointURL = URL(fileURLWithPath: checkpointPath, isDirectory: true)
    let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
    let profile = try TaskEvaluationProfile.profile(task: task.rawValue)
    let determinism = try makeDeterminism(tier: tier)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
    let gains = try ImuRateDampingCutGains(
      kp: kp,
      kd: kd,
      yawDamping: yawDamping,
      hoverThrustScale: hoverScale
    )
    let result = try await ReferenceQuadrotorDAggerRelabelService().relabel(
      ReferenceQuadrotorDAggerRelabelRequest(
        profile: profile,
        checkpointURL: checkpointURL,
        outputURL: outputURL,
        evaluatorConfig: ManasMLXReferenceQuadrotorCheckpointEvaluatorConfig(
          robotManifestPath: model,
          determinism: determinism,
          schedule: schedule,
          gains: gains,
          useQualityGating: false
        ),
        determinism: determinism,
        gains: gains,
        includeSuccessful: includeSuccessful
      )
    )
    print("daggerRelabelCTBR=true")
    print("relabeledEpisodes=\(result.relabeledEpisodes)")
    print("relabeledSteps=\(result.relabeledSteps)")
    print("output=\(result.outputURL.path)")
  }
}

struct WriteCTBRCheckpoint: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "write-ctbr-checkpoint",
    abstract: "Write a strict temporal CTBR Manas bundle for reference quadrotor training."
  )

  enum CommandError: Error, CustomStringConvertible {
    case missingOutput
    case outputParentMissing(String)
    case outputParentIsFile(String)
    case invalidHiddenSize(Int)
    case invalidObservationDimension(Int)
    case invalidHistoryLength(Int)
    case outputMustBeManasBundle(String)
    case outputAlreadyExists(String)

    var description: String {
      switch self {
      case .missingOutput:
        return "missing-output"
      case .outputParentMissing(let path):
        return "output-parent-missing: \(path)"
      case .outputParentIsFile(let path):
        return "output-parent-is-file: \(path)"
      case .invalidHiddenSize(let hiddenSize):
        return "invalid-hidden-size: \(hiddenSize)"
      case .invalidObservationDimension(let value):
        return "invalid-observation-dimension: \(value)"
      case .invalidHistoryLength(let value):
        return "invalid-history-length: \(value)"
      case .outputMustBeManasBundle(let path):
        return "output-must-be-manasbundle: \(path)"
      case .outputAlreadyExists(let path):
        return "output-already-exists: \(path)"
      }
    }
  }

  @Option(name: .customLong("output"), help: "Destination .manasbundle directory.")
  var output: String = ""

  @Option(name: .customLong("name"), help: "Bundle display name.")
  var name: String = "Reference Quadrotor Temporal CTBR"

  @Option(
    name: .customLong("model"),
    help: "Robot manifest path used to bind embodiment hash/profile metadata.")
  var model: String = KuyuUIModelPaths.defaultRobotManifestPath()

  @Option(name: .customLong("task"), help: "Reference task contract to use for starter sizing.")
  var task: CTBRCheckpointTaskChoice = .attitude

  @Option(name: .customLong("hidden-size"), help: "Temporal actor-critic hidden size.")
  var hiddenSize: Int = 256

  @Option(
    name: .customLong("observation-dimension"),
    help: "Optional actor observation channel override. Defaults to the selected task contract.")
  var observationDimension: Int?

  @Option(
    name: .customLong("history-length"),
    help: "Optional temporal window override. Defaults to the selected task contract.")
  var historyLength: Int?

  func run() throws {
    let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedOutput.isEmpty else {
      throw CommandError.missingOutput
    }
    guard hiddenSize > 0 else {
      throw CommandError.invalidHiddenSize(hiddenSize)
    }
    if let observationDimension, observationDimension <= 0 {
      throw CommandError.invalidObservationDimension(observationDimension)
    }
    if let historyLength, historyLength <= 0 {
      throw CommandError.invalidHistoryLength(historyLength)
    }

    let outputURL = URL(fileURLWithPath: trimmedOutput).standardizedFileURL
    guard outputURL.pathExtension == "manasbundle" else {
      throw CommandError.outputMustBeManasBundle(outputURL.path)
    }
    guard !FileManager.default.fileExists(atPath: outputURL.path) else {
      throw CommandError.outputAlreadyExists(outputURL.path)
    }
    let parentURL = outputURL.deletingLastPathComponent()
    var isDirectory: ObjCBool = false
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: parentURL.path, isDirectory: &isDirectory) else {
      throw CommandError.outputParentMissing(parentURL.path)
    }
    guard isDirectory.boolValue else {
      throw CommandError.outputParentIsFile(parentURL.path)
    }

    let robotManifestPath = KuyuUIModelPaths.resolveRobotManifestPath(model)
    let embodiment = try loadEmbodiment(modelPath: robotManifestPath)
    let taskMode = simulationTaskMode(from: task)
    let starterContract = try ReferenceQuadrotorStarterCheckpointContractService().contract(
      taskMode: taskMode,
      observationChannelCountOverride: observationDimension
    )
    let resolvedHistoryLength = historyLength ?? starterContract.historyLength
    let policyContract = ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(
      observationDimension: starterContract.expectedObservationChannelCount,
      historyLength: resolvedHistoryLength
    )
    let manifest = try ManasMLXTemporalCheckpointWriter().write(
      request: ManasMLXTemporalCheckpointWriteRequest(
        checkpointURL: outputURL,
        name: name,
        policyContract: policyContract,
        observationContract: starterContract.observationContract,
        actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
        embodiment: embodiment,
        hiddenSize: hiddenSize,
        initializationSeed: starterContract.initializationSeed,
        starterActionMean: starterContract.starterActionMean
      )
    )
    _ = try ManasMLXRuntimeReadinessService().report(
      for: ManasMLXRuntimeReadinessRequest(
        robotManifestPath: robotManifestPath,
        sourceCheckpointURL: outputURL,
        requireSourceCheckpoint: true
      )
    )

    print("ctbrCheckpointWritten=true")
    print("path=\(outputURL.path)")
    print("task=\(task.rawValue)")
    print("modelFamily=\(ManasMLXTemporalCheckpointManifest.modelFamily)")
    print("schemaVersion=\(manifest.schemaVersion)")
    print("historyLength=\(manifest.config.batchSpec.historyLength)")
    print("observationDimension=\(manifest.config.batchSpec.observationDimension)")
    print("observationSchemaID=\(manifest.observationSchemaID)")
    print("privilegedDimension=\(manifest.config.batchSpec.privilegedDimension)")
    print("actionDimension=\(manifest.config.batchSpec.actionDimension)")
    print("hiddenSize=\(manifest.config.hiddenSize)")
    print("embodimentBound=\(embodiment != nil)")
    print("robotManifest=\(robotManifestPath)")
  }
}

struct ProbeManasSuite: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "probe-manas-suite",
    abstract: "Run a matrix of ManasMLX E2E probes and write a suite summary."
  )

  @Option(help: "Determinism tier: tier0, tier1, tier2.")
  var tier: TierChoice = .tier1

  @Option(help: "Comma-separated task list: attitude,lift,singleLift. Defaults to all.")
  var tasks: String = "attitude,lift,singleLift"

  @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
  var cutPeriodSteps: UInt64 = 2

  @Option(help: "Robot manifest path.")
  var model: String = ""

  @Option(
    name: .customLong("source-checkpoint"),
    help: "Optional source checkpoint directory containing model.json and core.safetensors.")
  var sourceCheckpointPath: String?

  @Option(name: .customLong("artifact-root"), help: "Directory where suite artifacts are written.")
  var artifactRootPath: String?

  @Option(help: "Training iterations per task.")
  var iterations: Int = 1

  @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
  var sequenceLength: Int = 16

  @Option(name: .customLong("epochs"), help: "Epochs per iteration.")
  var epochs: Int = 1

  @Option(name: .customLong("lr"), help: "Learning rate.")
  var learningRate: Double = 0.001

  @Option(name: .customLong("max-batches"), help: "Maximum training batches for smoke tests.")
  var maxBatches: Int?

  @Option(
    help:
      "Worker count for future parallel training probes. Values greater than 1 require --source-checkpoint."
  )
  var workers: Int = 1

  @Option(
    name: .customLong("min-delta"),
    help: "Minimum trained-vs-initial score delta required for probe success.")
  var minDelta: Double = 0

  @Option(help: "kp gain for baseline controller.")
  var kp: Double = 2.0

  @Option(help: "kd gain for baseline controller.")
  var kd: Double = 0.25

  @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
  var yawDamping: Double = 0.2

  @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
  var hoverScale: Double = 1.0

  @Option(
    name: .customLong("mlx-seed"), help: "Base MLX random seed. Each task increments this value.")
  var mlxSeed: UInt64?

  @Flag(name: .customLong("no-aux"), help: "Disable aux prediction loss for MLX.")
  var noAux: Bool = false

  @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
  var noQualityGate: Bool = false

  @MainActor
  mutating func run() async throws {
    guard iterations > 0 else {
      throw ValidationError("--iterations must be greater than 0.")
    }
    guard sequenceLength > 0 else {
      throw ValidationError("--sequence must be greater than 0.")
    }
    guard epochs > 0 else {
      throw ValidationError("--epochs must be greater than 0.")
    }
    if let maxBatches, maxBatches <= 0 {
      throw ValidationError("--max-batches must be positive when specified.")
    }
    guard workers > 0 else {
      throw ValidationError("--workers must be greater than 0.")
    }
    let selectedTasks = try parseProbeTasks(tasks)
    let sourceCheckpointURL =
      sourceCheckpointPath
      .flatMap { path -> URL? in
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed, isDirectory: true)
      }
    if workers > 1, sourceCheckpointURL == nil {
      throw ValidationError(
        "--workers greater than 1 requires --source-checkpoint so every worker can lease an isolated snapshot."
      )
    }

    let suiteRoot: URL
    if let artifactRootPath,
      !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      suiteRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
    } else {
      suiteRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-probe-suite-\(UUID().uuidString)", isDirectory: true)
    }
    try FileManager.default.createDirectory(at: suiteRoot, withIntermediateDirectories: true)

    var entries: [ManasProbeSuiteEntry] = []
    for (taskIndex, task) in selectedTasks.enumerated() {
      let taskRoot = suiteRoot.appendingPathComponent(task.rawValue, isDirectory: true)
      let result = try await runCLIManasProbe(
        task: task,
        tier: tier,
        cutPeriodSteps: cutPeriodSteps,
        model: model,
        sourceCheckpointURL: sourceCheckpointURL,
        artifactRoot: taskRoot,
        iterations: iterations,
        sequenceLength: sequenceLength,
        epochs: epochs,
        learningRate: learningRate,
        maxBatches: maxBatches,
        workers: workers,
        minDelta: minDelta,
        kp: kp,
        kd: kd,
        yawDamping: yawDamping,
        hoverScale: hoverScale,
        useAux: !noAux,
        useQualityGating: !noQualityGate,
        mlxSeed: mlxSeed.map { $0 + UInt64(taskIndex) },
        printEvents: false
      )
      let artifacts = try KuyuCLITrainingArtifactReader().validatedProbeArtifacts(in: taskRoot)
      let entry = ManasProbeSuiteEntry(
        task: task.rawValue,
        artifactPath: taskRoot.path,
        terminalState: result.manifest.terminalState.rawValue,
        trainingCheckpoint: result.comparison.checkpointDecision.rawValue,
        probeCheckpoint: result.probeCheckpointDecision.state.rawValue,
        selectedCheckpointRole: result.comparison.selectedCheckpointRole.rawValue,
        selectedCheckpointPath: result.comparison.selectedCheckpointURL?.path,
        reloadSucceeded: result.comparison.reloadSucceeded,
        teacherScore: result.comparison.teacherScore,
        initialScore: result.comparison.initialScore,
        trainedScore: result.comparison.trainedScore,
        scoreDelta: result.comparison.scoreDelta,
        referenceSatisfied: result.comparison.referenceSatisfied,
        policySatisfied: result.comparison.policySatisfied,
        probeAccepted: result.comparison.probeAccepted,
        probeRejectionReasons: result.comparison.probeRejectionReasons,
        meetsMinimumDelta: result.comparison.meetsMinimumDelta,
        safetyNonRegression: result.comparison.safetyNonRegression,
        teacherDivergenceNonRegression: result.comparison.teacherDivergenceNonRegression,
        teacherDriveDivergenceNonRegression: result.comparison.teacherDriveDivergenceNonRegression,
        teacherMotorDivergenceNonRegression: result.comparison.teacherMotorDivergenceNonRegression,
        teacherAltitudeDivergenceNonRegression: result.comparison
          .teacherAltitudeDivergenceNonRegression,
        initialTeacherDriveAverageMAE: result.comparison.initialTeacherDriveAverageMAE,
        trainedTeacherDriveAverageMAE: result.comparison.trainedTeacherDriveAverageMAE,
        initialTeacherMotorAverageMAE: result.comparison.initialTeacherMotorAverageMAE,
        trainedTeacherMotorAverageMAE: result.comparison.trainedTeacherMotorAverageMAE,
        initialTeacherFinalAltitudeDelta: result.comparison.initialTeacherFinalAltitudeDelta,
        trainedTeacherFinalAltitudeDelta: result.comparison.trainedTeacherFinalAltitudeDelta,
        trainedFailureReasons: result.trained?.diagnostics.failureReasons ?? [],
        teacherAverageDriveActivation: result.teacher.diagnostics.averageDriveActivation,
        trainedAverageDriveActivation: result.trained?.diagnostics.averageDriveActivation,
        teacherAverageDriveActivationByIndex: result.teacher.diagnostics
          .averageDriveActivationByIndex,
        trainedAverageDriveActivationByIndex: result.trained?.diagnostics
          .averageDriveActivationByIndex,
        trainedAverageMotorFinalOutputByIndex: result.trained?.diagnostics
          .averageMotorFinalOutputByIndex,
        trainedFinalAltitudeZ: result.trained?.diagnostics.finalAltitudeZ,
        trainedFinalVerticalVelocityZ: result.trained?.diagnostics.finalVerticalVelocityZ,
        metricsCount: artifacts.training.metrics.count,
        recoveryRelabelAttempted: result.recoveryRelabelStatus.attempted,
        recoveryRelabelDatasetPath: result.recoveryRelabelStatus.datasetDirectory?.path,
        recoveryRelabelEntryCount: result.recoveryRelabelStatus.report?.relabeledEntryCount,
        recoveryRelabelCutStepCount: result.recoveryRelabelStatus.report?.relabeledCutStepCount,
        failureReason: result.manifest.failureReason
      )
      entries.append(entry)
      print(
        "[probe-suite] task=\(task.rawValue) terminal=\(entry.terminalState) probeAccepted=\(entry.probeAccepted) reasons=\(entry.probeRejectionReasons.joined(separator: ",")) probeCheckpoint=\(entry.probeCheckpoint) reload=\(entry.reloadSucceeded) artifactValid=true"
      )
      print(
        "[probe-suite] selectedCheckpoint role=\(entry.selectedCheckpointRole) path=\(entry.selectedCheckpointPath ?? "n/a")"
      )
      if let trainedMotorMAE = entry.trainedTeacherMotorAverageMAE {
        print(
          "[probe-suite] teacherDivergence motorMAE=\(String(format: "%.6f", trainedMotorMAE)) driveMAE=\(formatOptional(entry.trainedTeacherDriveAverageMAE)) altitudeDelta=\(formatOptional(entry.trainedTeacherFinalAltitudeDelta)) nonRegression=\(entry.teacherDivergenceNonRegression)"
        )
      }
      if entry.recoveryRelabelAttempted {
        print(
          "[probe-suite] recoveryRelabel entries=\(entry.recoveryRelabelEntryCount ?? 0) cutSteps=\(entry.recoveryRelabelCutStepCount ?? 0) path=\(entry.recoveryRelabelDatasetPath ?? "n/a")"
        )
      }
    }

    let summary = ManasProbeSuiteSummary(
      suiteID: "probe-suite-\(UUID().uuidString)",
      startedAt: Date(),
      artifactRoot: suiteRoot.path,
      entries: entries
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(summary).write(
      to: suiteRoot.appendingPathComponent("probe-suite-summary.json"),
      options: [.atomic]
    )
    print("[probe-suite] artifacts path=\(suiteRoot.path)")
    print(
      "[probe-suite] completed=\(entries.filter { $0.terminalState == LearningRunTerminalState.completed.rawValue }.count) rejected=\(entries.filter { $0.terminalState == LearningRunTerminalState.rejected.rawValue }.count) failed=\(entries.filter { $0.terminalState == LearningRunTerminalState.failed.rawValue }.count)"
    )
  }
}

struct TrainManasCore: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "train-manas-core",
    abstract: "Train Manas Core from an existing Kuyu/Manas supervised dataset directory."
  )

  @Option(
    help:
      "Dataset root containing scenario subdirectories or a single meta.json/records.jsonl pair.")
  var dataset: String

  @Option(help: "Output checkpoint directory.")
  var output: String

  @Option(
    name: .customLong("source-checkpoint"),
    help: "Optional source checkpoint directory to continue training from.")
  var sourceCheckpointPath: String?

  @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
  var sequenceLength: Int = 16

  @Option(name: .customLong("epochs"), help: "Epochs.")
  var epochs: Int = 3

  @Option(name: .customLong("lr"), help: "Learning rate.")
  var learningRate: Double = 0.0001

  @Option(name: .customLong("max-batches"), help: "Maximum training batches.")
  var maxBatches: Int?

  @Option(
    name: .customLong("mlx-seed"), help: "Optional MLX random seed for reproducible initialization."
  )
  var mlxSeed: UInt64?

  @Flag(name: .customLong("no-aux"), help: "Disable aux prediction loss for MLX.")
  var noAux: Bool = false

  @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
  var noQualityGate: Bool = false

  @ManasMLXExecutionActor
  mutating func run() async throws {
    guard sequenceLength > 0 else {
      throw ValidationError("--sequence must be greater than 0.")
    }
    guard epochs > 0 else {
      throw ValidationError("--epochs must be greater than 0.")
    }
    if let maxBatches, maxBatches <= 0 {
      throw ValidationError("--max-batches must be positive when specified.")
    }
    if let mlxSeed {
      print("[train-manas-core] mlxSeed=\(mlxSeed)")
    }

    let datasetURL = URL(fileURLWithPath: dataset, isDirectory: true)
    let outputURL = URL(fileURLWithPath: output, isDirectory: true)
    let store = ManasMLXModelStore()
    if let sourceCheckpointPath,
      !sourceCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      let sourceURL = URL(fileURLWithPath: sourceCheckpointPath, isDirectory: true)
      _ = try store.loadModel(from: sourceURL)
      print("[train-manas-core] sourceCheckpoint=\(sourceURL.path)")
    }

    let result = try await store.trainCore(
      datasetURL: datasetURL,
      sequenceLength: sequenceLength,
      learningRate: learningRate,
      epochs: epochs,
      useAux: !noAux,
      useQualityGating: !noQualityGate,
      initializationSeed: mlxSeed,
      maxBatches: maxBatches
    )
    let manifest = try store.saveModel(to: outputURL)
    let reloadedStore = ManasMLXModelStore()
    _ = try reloadedStore.loadModel(from: outputURL)
    let reloadedOpenLoop = try reloadedStore.evaluateOpenLoopDriveFit(
      datasetURL: datasetURL,
      sequenceLength: sequenceLength,
      useQualityGating: !noQualityGate,
      maxBatches: maxBatches
    )

    print("[train-manas-core] dataset=\(datasetURL.path)")
    print("[train-manas-core] checkpoint=\(outputURL.path)")
    print(
      "[train-manas-core] model=\(manifest.name) finalLoss=\(String(format: "%.6f", result.finalLoss)) epochs=\(result.epochs)"
    )
    print(
      "[train-manas-core] openLoopDriveMAE=\(formatOptional(result.openLoopDriveMAE)) predictionAverage=\(formatOptional(result.openLoopPredictionAverage)) targetAverage=\(formatOptional(result.openLoopTargetAverage)) firstPrediction=\(formatOptional(result.openLoopFit?.firstPrediction)) firstTarget=\(formatOptional(result.openLoopFit?.firstTarget))"
    )
    print(
      "[train-manas-core] reloadedOpenLoopDriveMAE=\(formatOptional(reloadedOpenLoop?.meanAbsoluteError)) predictionAverage=\(formatOptional(reloadedOpenLoop?.predictionAverage)) targetAverage=\(formatOptional(reloadedOpenLoop?.targetAverage)) firstPrediction=\(formatOptional(reloadedOpenLoop?.firstPrediction)) firstTarget=\(formatOptional(reloadedOpenLoop?.firstTarget))"
    )
  }
}

struct MixTrainingDatasets: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mix-training-datasets",
    abstract: "Mix multiple Kuyu/Manas supervised dataset roots into one training dataset root."
  )

  @Option(
    name: .customLong("input"), help: "Input dataset root. Repeat this option for multiple roots.")
  var inputs: [String] = []

  @Option(help: "Output mixed dataset root.")
  var output: String

  mutating func run() throws {
    guard !inputs.isEmpty else {
      throw ValidationError("At least one --input is required.")
    }
    let sourceURLs = inputs.map { URL(fileURLWithPath: $0, isDirectory: true) }
    let outputURL = URL(fileURLWithPath: output, isDirectory: true)
    let manifest = try TrainingDatasetMixer().mix(sources: sourceURLs, to: outputURL)
    print("[mix-training-datasets] output=\(outputURL.path)")
    print(
      "[mix-training-datasets] datasets=\(manifest.datasetCount) records=\(manifest.totalRecordCount)"
    )
    for source in manifest.sources {
      print(
        "[mix-training-datasets] sourceIndex=\(source.index) datasets=\(source.copiedDatasetCount) records=\(source.copiedRecordCount) path=\(source.path)"
      )
    }
  }
}

struct EvaluateManasCheckpoint: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "evaluate-manas-checkpoint",
    abstract:
      "Evaluate a ManasMLX checkpoint against a teacher baseline without additional training."
  )

  @Option(help: "Task suite to evaluate: attitude, lift, or singleLift.")
  var task: RolloutTaskChoice = .attitude

  @Option(help: "Determinism tier: tier0, tier1, tier2.")
  var tier: TierChoice = .tier1

  @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
  var cutPeriodSteps: UInt64 = 2

  @Option(help: "Robot manifest path.")
  var model: String = ""

  @Option(
    name: .customLong("checkpoint"),
    help: "Checkpoint directory containing model.json, core.safetensors, and reflex.safetensors.")
  var checkpointPath: String

  @Option(
    name: .customLong("artifact-root"), help: "Directory where evaluation artifacts are written.")
  var artifactRootPath: String

  @Option(help: "kp gain for teacher baseline.")
  var kp: Double = 2.0

  @Option(help: "kd gain for teacher baseline.")
  var kd: Double = 0.25

  @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for teacher baseline.")
  var yawDamping: Double = 0.2

  @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
  var hoverScale: Double = 1.0

  @Flag(
    name: .customLong("no-quality-gate"), help: "Disable quality gating for ManasMLX evaluation.")
  var noQualityGate: Bool = false

  @Flag(
    name: .customLong("require-policy-pass"),
    help:
      "Exit non-zero unless the typed checkpoint evaluation artifact passes strict policy validation."
  )
  var requirePolicyPass: Bool = false

  @MainActor
  mutating func run() async throws {
    let checkpointURL = URL(fileURLWithPath: checkpointPath, isDirectory: true)
    let artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
    let profile = try TaskEvaluationProfile.profile(task: task.rawValue)
    let determinism = try makeDeterminism(tier: tier)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
    let gains = try ImuRateDampingCutGains(
      kp: kp,
      kd: kd,
      yawDamping: yawDamping,
      hoverThrustScale: hoverScale
    )
    let evaluationResult = try await ReferenceQuadrotorCheckpointEvaluationService().evaluate(
      ReferenceQuadrotorCheckpointEvaluationRunRequest(
        profile: profile,
        checkpointURL: checkpointURL,
        artifactRoot: artifactRoot,
        evaluatorConfig: ManasMLXReferenceQuadrotorCheckpointEvaluatorConfig(
          robotManifestPath: model,
          determinism: determinism,
          schedule: schedule,
          gains: gains,
          useQualityGating: !noQualityGate
        ),
        requiresPolicyPass: requirePolicyPass
      )
    )
    let summary = evaluationResult.summary
    let g1AcceptanceReport = evaluationResult.acceptance.g1Attitude

    print(
      "[evaluate-manas-checkpoint] task=\(summary.task) profile=\(summary.profileID) policyPassed=\(summary.policyPassed) score=\(String(format: "%.6f", summary.policyScore)) teacherScore=\(String(format: "%.6f", summary.teacherScore))"
    )
    print(
      "[evaluate-manas-checkpoint] motorMAE=\(formatOptional(summary.motorMAE)) driveMAE=\(formatOptional(summary.driveMAE)) finalAltitudeDelta=\(formatOptional(summary.finalAltitudeDelta)) failures=\(summary.failureReasons.joined(separator: ","))"
    )
    if let g1AcceptanceReport {
      print(
        "[evaluate-manas-checkpoint] g1Acceptance accepted=\(g1AcceptanceReport.accepted) taskPassRate=\(String(format: "%.6f", g1AcceptanceReport.taskPassRate)) safetyViolationRate=\(String(format: "%.6f", g1AcceptanceReport.safetyViolationRate)) failures=\(g1AcceptanceReport.failureReasons.joined(separator: ",")) artifact=\(artifactRoot.appendingPathComponent(ReferenceQuadrotorG1AttitudeAcceptanceReport.fileName).path)"
      )
    }
    if let diagnostics = summary.diagnostics {
      print(
        "[evaluate-manas-checkpoint] diagnostics worstAltitudeDelta=\(formatOptional(diagnostics.worstFinalAltitudeDelta)) worstVzDelta=\(formatOptional(diagnostics.worstFinalVerticalVelocityDelta)) earliestAltitudeDivergence=\(formatOptional(diagnostics.earliestAltitudeDivergenceTime))"
      )
      if let failed = diagnostics.scenarioComparisons.first(where: { $0.policyFailureReason != nil }
      ) {
        print(
          "[evaluate-manas-checkpoint] firstFailedScenario id=\(failed.scenarioID) seed=\(failed.seed) reason=\(failed.policyFailureReason ?? "n/a") failureTime=\(formatOptional(failed.policyFailureTime)) motorMAE=\(formatOptional(failed.motorOutputMAE)) initialDrive=\(formatOptional(failed.policyInitialDriveActivation)) earlyDriveAvg=\(formatOptional(failed.policyEarlyDriveActivationAverage)) teacherEarlyDriveAvg=\(formatOptional(failed.teacherEarlyDriveActivationAverage))"
        )
      }
    }
    print("[evaluate-manas-checkpoint] artifacts path=\(artifactRoot.path)")
  }
}

struct RunFoundationAcceptance: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "foundation-acceptance",
    abstract:
      "Train or promote a completed reference quadrotor campaign, then run final G1 and M2 acceptance."
  )

  @Option(name: .customLong("source-checkpoint"), help: "Source ManasMLX checkpoint directory.")
  var sourceCheckpointPath: String = ""

  @Option(
    name: .customLong("completed-campaign-artifact-root"),
    help: "Completed campaign at <artifact-root>/campaign to validate and promote without retraining."
  )
  var completedCampaignArtifactRootPath: String?

  @Option(
    name: .customLong("artifact-root"),
    help: "Directory where foundation acceptance artifacts are written.")
  var artifactRootPath: String

  @Option(help: "Comma-separated explicit campaign seed values.")
  var seeds: String?

  @Option(
    name: .customLong("seed-count"),
    help: "Generate sequential campaign seeds from 1 through this count.")
  var seedCount: Int = 1

  @Option(help: "Population size per seed.")
  var population: Int = 100

  @Option(help: "Maximum generation budget per seed.")
  var generations: Int = 1_000

  @Option(name: .customLong("elite-count"), help: "Number of candidates selected as parents.")
  var eliteCount: Int = 10

  @Option(help: "Worker count for rollout regression.")
  var workers: Int = 1

  @Option(
    name: .customLong("candidate-evaluation-concurrency"),
    help: "Maximum Manas candidate evaluations to run concurrently.")
  var candidateEvaluationConcurrency: Int = 100

  @Option(
    help:
      "Comma-separated attitude campaign suite list. Final G1 acceptance always evaluates full KUY-ATT-1."
  )
  var suites: String = "0"

  @Option(help: "Episodes per candidate regression.")
  var episodes: Int = 1

  @Option(help: "Determinism tier: tier0, tier1, tier2.")
  var tier: LearningCampaignTier = .tier1

  @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
  var cutPeriodSteps: UInt64 = 2

  @Option(help: "Robot manifest path.")
  var model: String = KuyuUIModelPaths.defaultRobotManifestPath()

  @Option(
    name: .customLong("mutation-rate"),
    help: "Mutation rate passed to the ManasMLX variation provider.")
  var mutationRate: Double = 0.14

  @Option(name: .customLong("mutation-noise-scale"), help: "Gaussian mutation noise scale.")
  var mutationNoiseScale: Double = 0.025

  @Flag(
    name: .customLong("adaptive-mutation"), inversion: .prefixedNo,
    help: "Adapt mutation rate and noise scale after each generation gate result.")
  var adaptiveMutation: Bool = true

  @Option(
    name: .customLong("mutation-increase-factor"),
    help: "Adaptive mutation multiplier after a rejected generation.")
  var mutationIncreaseFactor: Double = 1.35

  @Option(
    name: .customLong("mutation-decay-factor"),
    help: "Adaptive mutation multiplier after an accepted generation.")
  var mutationDecayFactor: Double = 0.95

  @Option(name: .customLong("min-mutation-rate"), help: "Lower bound for adaptive mutation rate.")
  var minimumMutationRate: Double = 0

  @Option(name: .customLong("max-mutation-rate"), help: "Upper bound for adaptive mutation rate.")
  var maximumMutationRate: Double = 0.8

  @Option(
    name: .customLong("min-mutation-noise-scale"),
    help: "Lower bound for adaptive mutation noise scale.")
  var minimumMutationNoiseScale: Double = 0

  @Option(
    name: .customLong("max-mutation-noise-scale"),
    help: "Upper bound for adaptive mutation noise scale.")
  var maximumMutationNoiseScale: Double = 0.25

  @Flag(
    name: .customLong("early-stopping"), inversion: .prefixedNo,
    help: "Stop campaign after convergence patience is exhausted.")
  var earlyStopping: Bool = true

  @Option(
    name: .customLong("early-stopping-patience-generations"),
    help: "Generation patience for convergence early stopping.")
  var earlyStoppingPatienceGenerations: Int = 50

  @Option(
    name: .customLong("min-fitness-improvement"),
    help: "Minimum scalar-fitness improvement for convergence.")
  var minimumFitnessImprovement: Double = 0.001

  @Option(
    name: .customLong("min-task-pass-rate-improvement"),
    help: "Minimum task pass-rate improvement for convergence.")
  var minimumTaskPassRateImprovement: Double = 0.001

  @Option(
    name: .customLong("min-hold-time-ratio-improvement"),
    help: "Minimum hold-time ratio improvement for convergence.")
  var minimumHoldTimeRatioImprovement: Double = 0.001

  @Option(name: .customLong("search-strategy"), help: "Evolution search strategy.")
  var searchStrategy: EvolutionSearchStrategy = .qualityDiversity

  @Option(help: "Candidate variation mode: gaussian or copy.")
  var variation: LearningCampaignVariation = .gaussian

  @Option(
    name: .customLong("min-reward-average"),
    help: "Override the task default minimum reward average.")
  var minimumRewardAverage: Double?

  @Option(
    name: .customLong("reinforcement-warmup-duration"),
    help: "Seconds of tensor-world rollout per candidate for PPO warmup.")
  var reinforcementWarmupDuration: Double = 2

  @Option(
    name: .customLong("reinforcement-warmup-iterations"),
    help: "PPO iterations for the temporal CTBR warmup.")
  var reinforcementWarmupIterations: Int = 50

  @Option(
    name: .customLong("reinforcement-warmup-learning-rate"),
    help: "Learning rate for temporal CTBR PPO warmup.")
  var reinforcementWarmupLearningRate: Double = 3e-4

  @Option(
    name: .customLong("reinforcement-warmup-max-batches"),
    help: "Optional maximum rollout batches used by PPO warmup.")
  var reinforcementWarmupMaxBatches: Int?

  @Option(
    name: .customLong("reinforcement-min-iterations"),
    help: "Minimum PPO iteration count before plateau stopping is allowed.")
  var reinforcementMinimumIterations: Int = 10

  @Option(
    name: .customLong("reinforcement-plateau-window"),
    help: "Consecutive PPO iterations without material improvement required to stop on plateau.")
  var reinforcementPlateauWindow: Int = 10

  @Option(
    name: .customLong("reinforcement-unsafe-window"),
    help: "Consecutive unsafe PPO candidate rejections required to stop the reinforcement stage.")
  var reinforcementUnsafeWindow: Int = 2

  @Option(
    name: .customLong("min-incumbent-improvement"),
    help: "Minimum strict scalar-fitness improvement over the incumbent checkpoint.")
  var minimumIncumbentImprovement: Double = 0

  @Option(
    name: .customLong("min-novelty-score"),
    help: "Minimum novelty score required for a candidate to enter the evolution archive.")
  var minimumNoveltyScore: Double?

  @Option(
    name: .customLong("resource-sample-seconds"),
    help:
      "Resource sample interval recorded in the campaign plan. Use 0 to disable resource samples.")
  var resourceSampleSeconds: Double = 30

  @Option(
    name: .customLong("artifact-retention"), help: "Artifact retention mode: full or compact.")
  var artifactRetention: LearningCampaignArtifactRetentionMode = .compact

  @Option(name: .customLong("kp"), help: "IMU rate damping proportional gain.")
  var kp: Double = 0.35

  @Option(name: .customLong("kd"), help: "IMU rate damping derivative gain.")
  var kd: Double = 0.08

  @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain.")
  var yawDamping: Double = 0.04

  @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
  var hoverScale: Double = 1.0

  @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for ManasMLX rollout.")
  var noQualityGate: Bool = false

  @Flag(
    name: .customLong("allow-non-empty-artifact-root"),
    help: "Allow writing into a non-empty foundation artifact root.")
  var allowNonEmptyArtifactRoot: Bool = false

  @Flag(
    name: .customLong("skip-initial-parent-pass"),
    help:
      "Run the campaign even when the source checkpoint does not yet pass the attitude parent gate."
  )
  var skipInitialParentPass: Bool = false

  @Flag(
    name: .customLong("allow-rejected-artifact"),
    help: "Exit zero after writing a rejected foundation artifact.")
  var allowRejectedArtifact: Bool = false

  @Flag(
    name: .customLong("m2-benchmark"), inversion: .prefixedNo,
    help: "Run the service-backed M2 benchmark for the accepted checkpoint.")
  var m2Benchmark: Bool = true

  @Flag(
    name: .customLong("m2-optional"),
    help: "Record M2 benchmark evidence without requiring it for foundation acceptance.")
  var m2Optional: Bool = false

  @Option(
    name: .customLong("m2-suites"),
    help: "Comma-separated M2 benchmark suite list. Supported suites are 6, 7, and 8.")
  var m2Suites: String = "6,7,8"

  @Option(name: .customLong("m2-episodes-per-suite"), help: "Episodes per M2 benchmark suite.")
  var m2EpisodesPerSuite: Int = 3

  @Option(
    name: .customLong("m2-max-steps-per-episode"),
    help: "Optional maximum simulated steps per M2 benchmark episode.")
  var m2MaxStepsPerEpisode: Int?

  @Option(
    name: .customLong("stress-suite-manifests"),
    help: "Comma-separated stress suite manifest paths under --artifact-root.")
  var stressSuiteManifestPaths: String?

  @Option(
    name: .customLong("physics-corpus-acceptance-artifacts"),
    help: "Comma-separated descriptor corpus acceptance artifact paths under --artifact-root.")
  var physicsCorpusAcceptanceArtifactPaths: String?

  @Flag(
    name: .customLong("write-default-physics-corpus-acceptance"),
    help:
      "Generate a dynamic descriptor corpus acceptance artifact under --artifact-root before foundation acceptance."
  )
  var writeDefaultPhysicsCorpusAcceptance: Bool = false

  @Flag(
    name: .customLong("stress-suite-optional"),
    help: "Allow foundation acceptance to publish without stress suite evidence.")
  var stressSuiteOptional: Bool = false

  @Flag(
    name: .customLong("write-default-source-checkpoint"),
    help:
      "Generate a reference attitude source checkpoint under --artifact-root before foundation acceptance."
  )
  var writeDefaultSourceCheckpoint: Bool = false

  @Option(
    name: .customLong("default-source-checkpoint-name"),
    help: "Bundle display name for --write-default-source-checkpoint.")
  var defaultSourceCheckpointName: String = "Reference Quadrotor Foundation Source"

  @Option(
    name: .customLong("default-source-hidden-size"),
    help: "Temporal actor-critic hidden size used by --write-default-source-checkpoint.")
  var defaultSourceHiddenSize: Int = 256

  @Flag(
    name: .customLong("write-default-stress-suite-manifest"),
    help:
      "Generate a replay-verified reference M2 stress manifest under --artifact-root before foundation acceptance."
  )
  var writeDefaultStressSuiteManifest: Bool = false

  @Option(
    name: .customLong("default-stress-suite"),
    help: "Reference attitude stress suite used when --default-stress-scenario-suite is set.")
  var defaultStressSuite: Int = 8

  @Flag(
    name: .customLong("default-stress-scenario-suite"),
    help:
      "Generate the default stress manifest from --default-stress-suite instead of complete M2 benchmark coverage."
  )
  var defaultStressScenarioSuite: Bool = false

  @Option(
    name: .customLong("default-stress-episodes"),
    help:
      "Episodes used by the generated default stress manifest. Defaults to --m2-episodes-per-suite."
  )
  var defaultStressEpisodes: Int?

  @Option(
    name: .customLong("incumbent-project-evidence-pack"),
    help: "Directory containing the incumbent training-project evidence pack.")
  var incumbentProjectEvidencePackPath: String?

  @MainActor
  mutating func run() async throws {
    model = KuyuUIModelPaths.resolveRobotManifestPath(model)
    try validatePositiveFoundationAcceptanceInputs()
    if let minimumRewardAverage, !minimumRewardAverage.isFinite {
      throw ValidationError("--min-reward-average must be finite when specified.")
    }
    if let minimumNoveltyScore,
      !minimumNoveltyScore.isFinite || minimumNoveltyScore < 0
    {
      throw ValidationError("--min-novelty-score must be finite and non-negative when specified.")
    }
    let selectedSeeds = try seeds.map(parseFoundationAcceptanceSeeds)
    let selectedSuites = try parseFoundationAcceptanceSuites(suites)
    let selectedM2Suites = try parseFoundationAcceptanceM2Suites(m2Suites)
    let artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
      .standardizedFileURL
    let campaignSource = try foundationAcceptanceCampaignSource(artifactRoot: artifactRoot)
    let evidenceConfiguration = try foundationAcceptanceEvidenceConfiguration(
      campaignSource: campaignSource,
      artifactRoot: artifactRoot
    )
    var selectedStressSuiteManifestURLs = try parseFoundationAcceptanceStressSuiteManifestURLs(
      stressSuiteManifestPaths,
      artifactRoot: artifactRoot
    )
    var selectedPhysicsCorpusAcceptanceURLs =
      try parseFoundationAcceptancePhysicsCorpusAcceptanceURLs(
        physicsCorpusAcceptanceArtifactPaths,
        artifactRoot: artifactRoot
      )
    if writeDefaultStressSuiteManifest {
      let generatedStressManifestURL = defaultFoundationStressSuiteManifestURL(
        artifactRoot: artifactRoot
      )
      try appendFoundationAcceptanceStressSuiteManifestURL(
        generatedStressManifestURL,
        to: &selectedStressSuiteManifestURLs
      )
      try await writeDefaultFoundationStressSuiteManifest(
        outputURL: generatedStressManifestURL,
        artifactRoot: artifactRoot,
        configuration: evidenceConfiguration
      )
    }
    if writeDefaultPhysicsCorpusAcceptance {
      let generatedPhysicsCorpusURL = defaultFoundationPhysicsCorpusAcceptanceURL(
        artifactRoot: artifactRoot
      )
      try appendFoundationAcceptancePhysicsCorpusAcceptanceURL(
        generatedPhysicsCorpusURL,
        to: &selectedPhysicsCorpusAcceptanceURLs
      )
      try await writeDefaultFoundationPhysicsCorpusAcceptance(
        outputURL: generatedPhysicsCorpusURL,
        artifactRoot: artifactRoot,
        configuration: evidenceConfiguration
      )
    }
    let incumbentProjectEvidencePackDirectory =
      try parseFoundationAcceptanceProjectEvidencePackDirectory(
        incumbentProjectEvidencePackPath
      )
    let result = try await ReferenceQuadrotorFoundationAcceptanceService().run(
      ReferenceQuadrotorFoundationAcceptanceRequest(
        campaignSource: campaignSource,
        artifactRoot: artifactRoot,
        explicitSeeds: selectedSeeds,
        seedCount: seedCount,
        population: population,
        generations: generations,
        eliteCount: eliteCount,
        workers: workers,
        candidateEvaluationConcurrency: candidateEvaluationConcurrency,
        suites: selectedSuites,
        episodes: episodes,
        tier: tier,
        cutPeriodSteps: cutPeriodSteps,
        robotManifestPath: model,
        mutationRate: mutationRate,
        mutationNoiseScale: mutationNoiseScale,
        adaptiveMutationEnabled: adaptiveMutation,
        mutationIncreaseFactor: mutationIncreaseFactor,
        mutationDecayFactor: mutationDecayFactor,
        minimumMutationRate: minimumMutationRate,
        maximumMutationRate: maximumMutationRate,
        minimumMutationNoiseScale: minimumMutationNoiseScale,
        maximumMutationNoiseScale: maximumMutationNoiseScale,
        earlyStoppingEnabled: earlyStopping,
        earlyStoppingPatienceGenerations: earlyStoppingPatienceGenerations,
        minimumFitnessImprovement: minimumFitnessImprovement,
        minimumTaskPassRateImprovement: minimumTaskPassRateImprovement,
        minimumHoldTimeRatioImprovement: minimumHoldTimeRatioImprovement,
        searchStrategy: searchStrategy,
        variation: variation,
        minimumRewardAverage: minimumRewardAverage,
        reinforcementWarmupDuration: reinforcementWarmupDuration,
        reinforcementWarmupIterations: reinforcementWarmupIterations,
        reinforcementWarmupLearningRate: reinforcementWarmupLearningRate,
        reinforcementWarmupMaxBatches: reinforcementWarmupMaxBatches,
        reinforcementStopping: try TrainingReinforcementStoppingSettings(
          minimumIterationCount: reinforcementMinimumIterations,
          plateauWindow: reinforcementPlateauWindow,
          unsafeWindow: reinforcementUnsafeWindow
        ),
        minimumIncumbentImprovement: minimumIncumbentImprovement,
        minimumNoveltyScore: minimumNoveltyScore,
        resourceSampleSeconds: resourceSampleSeconds,
        artifactRetention: artifactRetention,
        kp: kp,
        kd: kd,
        yawDamping: yawDamping,
        hoverScale: hoverScale,
        qualityGateEnabled: !noQualityGate,
        allowsNonEmptyArtifactRoot: allowNonEmptyArtifactRoot,
        requiresInitialParentPass: !skipInitialParentPass,
        m2BenchmarkEnabled: m2Benchmark,
        m2BenchmarkRequired: !m2Optional,
        m2BenchmarkSuites: selectedM2Suites,
        m2BenchmarkEpisodesPerSuite: m2EpisodesPerSuite,
        m2BenchmarkMaxStepsPerEpisode: m2MaxStepsPerEpisode,
        stressSuiteEvidenceRequired: !stressSuiteOptional,
        stressSuiteManifestURLs: selectedStressSuiteManifestURLs,
        physicsCorpusAcceptanceURLs: selectedPhysicsCorpusAcceptanceURLs,
        incumbentProjectEvidencePackDirectory: incumbentProjectEvidencePackDirectory
      ),
      onEvent: { event in
        Self.printFoundationAcceptanceEvent(event)
      }
    )
    let artifact = try ReferenceQuadrotorFoundationAcceptanceArtifactValidator()
      .validatedArtifact(in: artifactRoot)
    print(
      "[foundation-acceptance] status=\(artifact.status.rawValue) accepted=\(artifact.accepted) campaignAccepted=\(artifact.campaignAcceptedCount)/\(artifact.campaignSeedCount)"
    )
    print("[foundation-acceptance] campaignSource=\(artifact.campaignProvenance.kind.rawValue)")
    if let sourceCheckpointPath = artifact.campaignProvenance.sourceCheckpointPath {
      print("[foundation-acceptance] sourceCheckpoint=\(sourceCheckpointPath)")
    }
    if let completedCampaignArtifactRootPath =
      artifact.campaignProvenance.completedCampaignArtifactRootPath
    {
      print("[foundation-acceptance] completedCampaign=\(completedCampaignArtifactRootPath)")
    }
    if let acceptedCheckpointPath = artifact.acceptedCheckpointPath {
      print("[foundation-acceptance] checkpoint=\(acceptedCheckpointPath)")
    }
    if let g1Acceptance = artifact.g1Acceptance {
      print(
        "[foundation-acceptance] g1 accepted=\(g1Acceptance.accepted) taskPassRate=\(String(format: "%.6f", g1Acceptance.taskPassRate)) safetyViolationRate=\(String(format: "%.6f", g1Acceptance.safetyViolationRate))"
      )
    }
    if let m2Decision = artifact.m2BenchmarkDecision {
      print(
        "[foundation-acceptance] m2 allPassed=\(m2Decision.allPassed) failedSuites=\(m2Decision.failedSuites.map(String.init).joined(separator: ","))"
      )
    }
    if let m2BenchmarkArtifactPath = artifact.m2BenchmarkArtifactPath {
      print("[foundation-acceptance] m2Artifact=\(m2BenchmarkArtifactPath)")
    }
    if let projectEvidencePackPath = artifact.trainingProjectEvidencePackPath {
      print("[foundation-acceptance] projectEvidencePack=\(projectEvidencePackPath)")
    }
    if let projectEvidenceComparison = result.projectEvidenceComparison {
      print(
        "[foundation-acceptance] projectEvidenceComparison decision=\(projectEvidenceComparison.decision.rawValue) dominantFactor=\(projectEvidenceComparison.dominantFactor.rawValue)"
      )
    }
    if !artifact.failureReasons.isEmpty {
      print("[foundation-acceptance] failures=\(artifact.failureReasons.joined(separator: ","))")
    }
    print(
      "[foundation-acceptance] artifact=\(artifactRoot.appendingPathComponent(ReferenceQuadrotorFoundationAcceptanceArtifact.fileName).path)"
    )
    guard artifact.accepted || allowRejectedArtifact else {
      throw ValidationError(
        "foundation acceptance rejected: \(artifact.failureReasons.joined(separator: ","))")
    }
  }

}

func formatOptional(_ value: Double?) -> String {
  guard let value else {
    return "n/a"
  }
  return String(format: "%.6f", value)
}

private struct ManasProbeSuiteSummary: Codable {
  let suiteID: String
  let startedAt: Date
  let artifactRoot: String
  let entries: [ManasProbeSuiteEntry]
}

private struct ManasProbeSuiteEntry: Codable {
  let task: String
  let artifactPath: String
  let terminalState: String
  let trainingCheckpoint: String
  let probeCheckpoint: String
  let selectedCheckpointRole: String
  let selectedCheckpointPath: String?
  let reloadSucceeded: Bool
  let teacherScore: Double
  let initialScore: Double
  let trainedScore: Double?
  let scoreDelta: Double?
  let referenceSatisfied: Bool
  let policySatisfied: Bool
  let probeAccepted: Bool
  let probeRejectionReasons: [String]
  let meetsMinimumDelta: Bool
  let safetyNonRegression: Bool
  let teacherDivergenceNonRegression: Bool
  let teacherDriveDivergenceNonRegression: Bool
  let teacherMotorDivergenceNonRegression: Bool
  let teacherAltitudeDivergenceNonRegression: Bool
  let initialTeacherDriveAverageMAE: Double?
  let trainedTeacherDriveAverageMAE: Double?
  let initialTeacherMotorAverageMAE: Double?
  let trainedTeacherMotorAverageMAE: Double?
  let initialTeacherFinalAltitudeDelta: Double?
  let trainedTeacherFinalAltitudeDelta: Double?
  let trainedFailureReasons: [String]
  let teacherAverageDriveActivation: Double?
  let trainedAverageDriveActivation: Double?
  let teacherAverageDriveActivationByIndex: [Double]?
  let trainedAverageDriveActivationByIndex: [Double]?
  let trainedAverageMotorFinalOutputByIndex: [Double]?
  let trainedFinalAltitudeZ: Double?
  let trainedFinalVerticalVelocityZ: Double?
  let metricsCount: Int
  let recoveryRelabelAttempted: Bool
  let recoveryRelabelDatasetPath: String?
  let recoveryRelabelEntryCount: Int?
  let recoveryRelabelCutStepCount: Int?
  let failureReason: String?
}

struct CheckEnvironments: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check-environments",
    abstract: "Validate Kuyu teacher environments before Manas training."
  )

  @Option(help: "Comma-separated task list: attitude,lift,singleLift. Defaults to all.")
  var tasks: String = "attitude,lift,singleLift"

  @Option(help: "Baseline controller to validate: activeAltitudeHold or sensorBaseline.")
  var controller: ControllerChoice = .activeAltitudeHold

  @Option(help: "Determinism tier: tier0, tier1, tier2.")
  var tier: TierChoice = .tier1

  @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
  var cutPeriodSteps: UInt64 = 2

  @Option(help: "Robot manifest path.")
  var model: String = ""

  @Option(
    name: .customLong("artifact-root"), help: "Directory where readiness artifacts are written.")
  var artifactRootPath: String?

  @Option(help: "kp gain for baseline controller.")
  var kp: Double = 2.0

  @Option(help: "kd gain for baseline controller.")
  var kd: Double = 0.25

  @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
  var yawDamping: Double = 0.2

  @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
  var hoverScale: Double = 1.0

  @Flag(
    name: .customLong("fail-on-not-ready"),
    help: "Exit with non-zero status if any environment is not ready.")
  var failOnNotReady: Bool = false

  @MainActor
  mutating func run() async throws {
    let selectedTasks = try parseProbeTasks(tasks).map(simulationTaskMode(from:))
    let selectedController = controllerSelection(from: controller)
    guard selectedController != .manasMLX else {
      throw ValidationError(
        "check-environments validates baseline environments only. Use activeAltitudeHold or sensorBaseline."
      )
    }

    let determinism = try makeDeterminism(tier: tier)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
    let parameters = try loadParameters(modelPath: model)
    let embodiment = try loadEmbodiment(modelPath: model)
    let gains = try ImuRateDampingCutGains(
      kp: kp,
      kd: kd,
      yawDamping: yawDamping,
      hoverThrustScale: hoverScale
    )
    let artifactRoot: URL
    if let artifactRootPath,
      !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
    } else {
      artifactRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          "kuyu-environment-readiness-\(UUID().uuidString)", isDirectory: true)
    }

    let report = try await ReferenceQuadrotorEnvironmentReadinessChecker().check(
      tasks: selectedTasks,
      controller: selectedController,
      parameters: parameters,
      schedule: schedule,
      determinism: determinism,
      gains: gains,
      robotManifestPath: model,
      embodiment: embodiment,
      artifactRoot: artifactRoot
    )

    for task in report.tasks {
      print(
        "[env] task=\(task.task) ready=\(task.ready) passed=\(task.suitePassed) score=\(String(format: "%.3f", task.score)) actionCoverage=\(String(format: "%.3f", task.scenarioActionCoverage)) dataset=\(task.datasetScenarioCount)/\(task.scenarioCount) failures=\(task.failureCount)"
      )
      if !task.failureReasons.isEmpty {
        print("[env] task=\(task.task) reasons=\(task.failureReasons.joined(separator: " | "))")
      }
    }
    print("[env] artifacts path=\(artifactRoot.path)")
    print("[env] allReady=\(report.allReady)")

    if failOnNotReady && !report.allReady {
      throw ExitCode.failure
    }
  }
}

struct CheckTrainingHarness: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check-training-harness",
    abstract: "Run Kuyu environment readiness and a ManasMLX supervised E2E training probe."
  )

  @Option(help: "Determinism tier: tier0, tier1, tier2.")
  var tier: TierChoice = .tier1

  @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
  var cutPeriodSteps: UInt64 = 2

  @Option(help: "Robot manifest path.")
  var model: String = ""

  @Option(
    name: .customLong("artifact-root"), help: "Directory where harness artifacts are written.")
  var artifactRootPath: String?

  @Option(
    name: .customLong("source-checkpoint"),
    help: "Optional source checkpoint directory to continue probe attempts from.")
  var sourceCheckpointPath: String?

  @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
  var sequenceLength: Int = 16

  @Option(name: .customLong("epochs"), help: "Epochs for the supervised ManasMLX probe.")
  var epochs: Int = 40

  @Option(name: .customLong("lr"), help: "Learning rate for the supervised ManasMLX probe.")
  var learningRate: Double = 0.001

  @Option(
    name: .customLong("max-batches"),
    help: "Maximum training batches for the supervised ManasMLX probe.")
  var maxBatches: Int = 64

  @Option(help: "Maximum probe attempts per task. Each attempt writes separate artifacts.")
  var attempts: Int = 3

  @Option(
    name: .customLong("recovery-repeat"),
    help: "Repeat recovery relabel datasets this many times when mixing retry training data.")
  var recoveryRepeat: Int = 1

  @Option(
    name: .customLong("mlx-seed"), help: "Base MLX random seed. Each retry increments this value.")
  var mlxSeed: UInt64 = 10_000

  @Option(help: "kp gain for baseline controller.")
  var kp: Double = 2.0

  @Option(help: "kd gain for baseline controller.")
  var kd: Double = 0.25

  @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
  var yawDamping: Double = 0.2

  @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
  var hoverScale: Double = 1.0

  @Flag(
    name: .customLong("include-lift-probe"),
    help: "Also run a lift probe. The default E2E learning gate is singleLift.")
  var includeLiftProbe: Bool = false

  @Flag(
    name: .customLong("require-task-solved"),
    help:
      "Require the trained policy to satisfy the full task suite, not only the harness smoke gate.")
  var requireTaskSolved: Bool = false

  @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
  var noQualityGate: Bool = false

  @MainActor
  mutating func run() async throws {
    guard sequenceLength > 0 else {
      throw ValidationError("--sequence must be greater than 0.")
    }
    guard epochs > 0 else {
      throw ValidationError("--epochs must be greater than 0.")
    }
    if maxBatches <= 0 {
      throw ValidationError("--max-batches must be positive when specified.")
    }
    guard attempts > 0 else {
      throw ValidationError("--attempts must be greater than 0.")
    }
    guard recoveryRepeat > 0 else {
      throw ValidationError("--recovery-repeat must be greater than 0.")
    }

    let artifactRoot: URL
    if let artifactRootPath,
      !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
    } else {
      artifactRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-training-harness-\(UUID().uuidString)", isDirectory: true)
    }
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)

    let determinism = try makeDeterminism(tier: tier)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
    let parameters = try loadParameters(modelPath: model)
    let embodiment = try loadEmbodiment(modelPath: model)
    let gains = try ImuRateDampingCutGains(
      kp: kp,
      kd: kd,
      yawDamping: yawDamping,
      hoverThrustScale: hoverScale
    )

    let environmentRoot = artifactRoot.appendingPathComponent(
      "environment-readiness", isDirectory: true)
    let environmentReport = try await ReferenceQuadrotorEnvironmentReadinessChecker().check(
      tasks: [.lift, .singleLift],
      controller: .teacherActiveAltitudeHold,
      parameters: parameters,
      schedule: schedule,
      determinism: determinism,
      gains: gains,
      robotManifestPath: model,
      embodiment: embodiment,
      artifactRoot: environmentRoot
    )
    for task in environmentReport.tasks {
      print(
        "[harness] env task=\(task.task) ready=\(task.ready) score=\(String(format: "%.3f", task.score)) dataset=\(task.datasetScenarioCount)/\(task.scenarioCount)"
      )
    }
    guard environmentReport.allReady else {
      let summary = CheckTrainingHarnessSummary(
        artifactRoot: artifactRoot.path,
        environmentReady: false,
        probes: [],
        selectedCandidate: nil,
        allPassed: false
      )
      try writeHarnessSummary(summary, to: artifactRoot)
      print("[harness] artifacts path=\(artifactRoot.path)")
      throw ExitCode.failure
    }

    var probeTasks: [RolloutTaskChoice] = [.singleLift]
    if includeLiftProbe {
      probeTasks.insert(.lift, at: 0)
    }
    let initialSourceCheckpointURL = sourceCheckpointURL(from: sourceCheckpointPath)
    let harnessGateService = ReferenceQuadrotorTrainingHarnessGateService()

    var probeEntries: [CheckTrainingHarnessProbeEntry] = []
    var acceptedAttempts: [String: Int] = [:]
    for task in probeTasks {
      var taskAccepted = false
      var currentSourceCheckpointURL = initialSourceCheckpointURL
      var recoveryDatasetURLs: [URL] = []
      for attempt in 1...attempts {
        let taskRoot = artifactRoot.appendingPathComponent(
          "probe-\(task.rawValue)-attempt-\(attempt)",
          isDirectory: true
        )
        let result = try await runCLIManasProbe(
          task: task,
          tier: tier,
          cutPeriodSteps: cutPeriodSteps,
          model: model,
          sourceCheckpointURL: currentSourceCheckpointURL,
          artifactRoot: taskRoot,
          iterations: 1,
          sequenceLength: sequenceLength,
          epochs: epochs,
          learningRate: learningRate,
          maxBatches: maxBatches,
          workers: 1,
          minDelta: 0,
          kp: kp,
          kd: kd,
          yawDamping: yawDamping,
          hoverScale: hoverScale,
          useAux: false,
          useQualityGating: !noQualityGate,
          mlxSeed: mlxSeed + UInt64(attempt - 1),
          additionalDatasetURLs: recoveryDatasetURLs,
          additionalDatasetRepeatCount: recoveryRepeat,
          printEvents: true
        )
        let repairSourceCheckpointURL = harnessGateService.repairSourceCheckpointURL(result: result)
        currentSourceCheckpointURL = repairSourceCheckpointURL
        if let recoveryDatasetURL = harnessGateService.acceptedRecoveryDatasetURL(result: result) {
          recoveryDatasetURLs.append(recoveryDatasetURL)
        }
        let artifacts = try KuyuCLITrainingArtifactReader().validatedProbeArtifacts(in: taskRoot)
        let taskSolved = harnessGateService.taskSolved(result: result)
        let harnessSatisfied = harnessGateService.satisfied(result: result)
        let gateReport = harnessGateService.report(
          result: result,
          requireTaskSolved: requireTaskSolved,
          postRegression: nil
        )
        let attemptDecision = try harnessGateService.attemptDecision(
          task: task.rawValue,
          attempt: attempt,
          gateReport: gateReport
        )
        let entry = CheckTrainingHarnessProbeEntry(
          task: task.rawValue,
          attempt: attempt,
          accepted: attemptDecision.accepted,
          artifactPath: taskRoot.path,
          terminalState: result.manifest.terminalState.rawValue,
          trainingCheckpoint: result.comparison.checkpointDecision.rawValue,
          probeCheckpoint: result.probeCheckpointDecision.state.rawValue,
          selectedCheckpointRole: result.comparison.selectedCheckpointRole.rawValue,
          selectedCheckpointPath: result.comparison.selectedCheckpointURL?.path,
          repairSourceCheckpointPath: repairSourceCheckpointURL?.path,
          reloadSucceeded: result.comparison.reloadSucceeded,
          teacherScore: result.comparison.teacherScore,
          initialScore: result.comparison.initialScore,
          trainedScore: result.comparison.trainedScore,
          scoreDelta: result.comparison.scoreDelta,
          policySatisfied: result.comparison.policySatisfied,
          harnessSatisfied: harnessSatisfied,
          taskSolved: taskSolved,
          trainedFailureReasons: result.trained?.diagnostics.failureReasons ?? [],
          trainedAverageDriveActivation: result.trained?.diagnostics.averageDriveActivation,
          teacherAverageDriveActivation: result.teacher.diagnostics.averageDriveActivation,
          trainedAverageDriveActivationByIndex: result.trained?.diagnostics
            .averageDriveActivationByIndex,
          teacherAverageDriveActivationByIndex: result.teacher.diagnostics
            .averageDriveActivationByIndex,
          trainedAverageMotorFinalOutputByIndex: result.trained?.diagnostics
            .averageMotorFinalOutputByIndex,
          trainedFinalAltitudeZ: result.trained?.diagnostics.finalAltitudeZ,
          trainedFinalVerticalVelocityZ: result.trained?.diagnostics.finalVerticalVelocityZ,
          metricsCount: artifacts.training.metrics.count,
          recoveryRelabelAttempted: result.recoveryRelabelStatus.attempted,
          recoveryRelabelDatasetPath: result.recoveryRelabelStatus.datasetDirectory?.path,
          recoveryRelabelEntryCount: result.recoveryRelabelStatus.report?.relabeledEntryCount,
          recoveryRelabelCutStepCount: result.recoveryRelabelStatus.report?.relabeledCutStepCount,
          gateReport: gateReport,
          postRegression: nil
        )
        probeEntries.append(entry)
        print(
          "[harness] probe task=\(task.rawValue) attempt=\(attempt) terminal=\(entry.terminalState) trainingCheckpoint=\(entry.trainingCheckpoint) probeCheckpoint=\(entry.probeCheckpoint) selected=\(entry.selectedCheckpointRole) repairSource=\(entry.repairSourceCheckpointPath ?? "n/a") recoveryDatasets=\(recoveryDatasetURLs.count) reload=\(entry.reloadSucceeded) harnessSatisfied=\(entry.harnessSatisfied) taskSolved=\(entry.taskSolved)"
        )
        if attemptDecision.accepted {
          acceptedAttempts[attemptDecision.task] = attemptDecision.attempt
          taskAccepted = true
          break
        }
      }
      if !taskAccepted {
        let allPassed = try harnessGateService.requiredTasksSatisfied(
          acceptedAttempts: acceptedAttempts,
          requiredTasks: probeTasks.map(\.rawValue)
        )
        let summary = CheckTrainingHarnessSummary(
          artifactRoot: artifactRoot.path,
          environmentReady: true,
          probes: probeEntries,
          selectedCandidate: harnessGateService.selectedCandidate(
            from: probeEntries.map(\.harnessSelectionInput)
          ),
          allPassed: allPassed
        )
        try writeHarnessSummary(summary, to: artifactRoot)
        print("[harness] artifacts path=\(artifactRoot.path)")
        throw ExitCode.failure
      }
    }

    let allPassed = try harnessGateService.requiredTasksSatisfied(
      acceptedAttempts: acceptedAttempts,
      requiredTasks: probeTasks.map(\.rawValue)
    )
    let summary = CheckTrainingHarnessSummary(
      artifactRoot: artifactRoot.path,
      environmentReady: true,
      probes: probeEntries,
      selectedCandidate: harnessGateService.selectedCandidate(
        from: probeEntries.map(\.harnessSelectionInput)
      ),
      allPassed: allPassed
    )
    try writeHarnessSummary(summary, to: artifactRoot)
    print("[harness] artifacts path=\(artifactRoot.path)")
    print("[harness] allPassed=\(allPassed)")
    if !allPassed {
      throw ExitCode.failure
    }
  }

  private func writeHarnessSummary(_ summary: CheckTrainingHarnessSummary, to artifactRoot: URL)
    throws
  {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(summary).write(
      to: artifactRoot.appendingPathComponent("training-harness-summary.json"),
      options: [.atomic]
    )
  }
}

struct CheckTrainingHarnessSweep: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check-training-harness-sweep",
    abstract: "Run the ManasMLX training harness across multiple MLX seeds and summarize stability."
  )

  @Option(help: "Determinism tier: tier0, tier1, tier2.")
  var tier: TierChoice = .tier1

  @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
  var cutPeriodSteps: UInt64 = 2

  @Option(help: "Robot manifest path.")
  var model: String = ""

  @Option(name: .customLong("artifact-root"), help: "Directory where sweep artifacts are written.")
  var artifactRootPath: String?

  @Option(
    name: .customLong("source-checkpoint"),
    help: "Optional source checkpoint directory to continue probe attempts from.")
  var sourceCheckpointPath: String?

  @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
  var sequenceLength: Int = 16

  @Option(name: .customLong("epochs"), help: "Epochs for each supervised ManasMLX probe.")
  var epochs: Int = 40

  @Option(name: .customLong("lr"), help: "Learning rate for each supervised ManasMLX probe.")
  var learningRate: Double = 0.001

  @Option(
    name: .customLong("max-batches"),
    help: "Maximum training batches for each supervised ManasMLX probe.")
  var maxBatches: Int = 64

  @Option(help: "Number of seed bases to evaluate.")
  var seeds: Int = 5

  @Option(help: "Comma-separated task list: lift,singleLift. Defaults to singleLift.")
  var tasks: String = "singleLift"

  @Option(help: "Maximum probe attempts per seed. Each attempt increments the seed.")
  var attempts: Int = 3

  @Option(
    name: .customLong("recovery-repeat"),
    help: "Repeat recovery relabel datasets this many times when mixing retry training data.")
  var recoveryRepeat: Int = 1

  @Option(name: .customLong("mlx-seed"), help: "Base MLX random seed for the sweep.")
  var mlxSeed: UInt64 = 10_000

  @Option(
    name: .customLong("min-success-rate"),
    help: "Minimum acceptable success rate in the range 0...1.")
  var minSuccessRate: Double = 1.0

  @Option(help: "kp gain for baseline controller.")
  var kp: Double = 2.0

  @Option(help: "kd gain for baseline controller.")
  var kd: Double = 0.25

  @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
  var yawDamping: Double = 0.2

  @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
  var hoverScale: Double = 1.0

  @Flag(
    name: .customLong("require-task-solved"),
    help:
      "Require each successful seed to satisfy the full task suite, not only the harness smoke gate."
  )
  var requireTaskSolved: Bool = false

  @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
  var noQualityGate: Bool = false

  @Flag(
    name: .customLong("post-regression"),
    help: "Run M2 rollout regression against each accepted checkpoint.")
  var postRegression: Bool = false

  @Option(
    name: .customLong("post-regression-suites"),
    help: "Comma-separated M2 suite list for post-training checkpoint regression: 6,7,8.")
  var postRegressionSuites: String = "6,7,8"

  @Option(
    name: .customLong("post-regression-episodes"),
    help: "Episodes per M2 suite during post-training checkpoint regression.")
  var postRegressionEpisodes: Int = 1

  @Flag(
    name: .customLong("post-regression-fail-on-truncation"),
    help: "Treat post-regression max-step truncation as a failure.")
  var postRegressionFailOnTruncation: Bool = false

  @Option(
    name: .customLong("post-regression-min-reward-average"),
    help:
      "Override the task default minimum reward average required for every post-regression rollout track."
  )
  var postRegressionMinRewardAverage: Double?

  @MainActor
  mutating func run() async throws {
    guard sequenceLength > 0 else {
      throw ValidationError("--sequence must be greater than 0.")
    }
    guard epochs > 0 else {
      throw ValidationError("--epochs must be greater than 0.")
    }
    guard maxBatches > 0 else {
      throw ValidationError("--max-batches must be greater than 0.")
    }
    guard seeds > 0 else {
      throw ValidationError("--seeds must be greater than 0.")
    }
    guard attempts > 0 else {
      throw ValidationError("--attempts must be greater than 0.")
    }
    guard recoveryRepeat > 0 else {
      throw ValidationError("--recovery-repeat must be greater than 0.")
    }
    guard minSuccessRate >= 0 && minSuccessRate <= 1 else {
      throw ValidationError("--min-success-rate must be in the range 0...1.")
    }
    guard postRegressionEpisodes > 0 else {
      throw ValidationError("--post-regression-episodes must be greater than 0.")
    }
    if let postRegressionMinRewardAverage, !postRegressionMinRewardAverage.isFinite {
      throw ValidationError("--post-regression-min-reward-average must be finite when specified.")
    }

    let artifactRoot: URL
    if let artifactRootPath,
      !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
    } else {
      artifactRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          "kuyu-training-harness-sweep-\(UUID().uuidString)", isDirectory: true)
    }
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)

    let determinism = try makeDeterminism(tier: tier)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
    let parameters = try loadParameters(modelPath: model)
    let embodiment = try loadEmbodiment(modelPath: model)
    let gains = try ImuRateDampingCutGains(
      kp: kp,
      kd: kd,
      yawDamping: yawDamping,
      hoverThrustScale: hoverScale
    )

    let environmentRoot = artifactRoot.appendingPathComponent(
      "environment-readiness", isDirectory: true)
    let selectedTasks = try parseProbeTasks(tasks)
    let selectedTaskNames = selectedTasks.map(\.rawValue)
    let selectedPostRegressionSuites = try parseRegressionSuites(postRegressionSuites)
    let selectedTaskModes = selectedTasks.map(simulationTaskMode(from:))
    let unsupportedTasks = selectedTasks.filter { $0 == .attitude }
    if !unsupportedTasks.isEmpty {
      throw ValidationError(
        "check-training-harness-sweep supports lift and singleLift. Attitude requires the rollout/regression path until ManasMLX multi-drive probe training is stabilized."
      )
    }

    let environmentReport = try await ReferenceQuadrotorEnvironmentReadinessChecker().check(
      tasks: selectedTaskModes,
      controller: .teacherActiveAltitudeHold,
      parameters: parameters,
      schedule: schedule,
      determinism: determinism,
      gains: gains,
      robotManifestPath: model,
      embodiment: embodiment,
      artifactRoot: environmentRoot
    )
    for task in environmentReport.tasks {
      print(
        "[harness-sweep] env task=\(task.task) ready=\(task.ready) score=\(String(format: "%.3f", task.score)) dataset=\(task.datasetScenarioCount)/\(task.scenarioCount)"
      )
    }

    guard environmentReport.allReady else {
      let summary = CheckTrainingHarnessSweepSummary(
        artifactRoot: artifactRoot.path,
        startedAt: Date(),
        environmentReady: false,
        requirement: requirementName,
        tasks: selectedTaskNames,
        seedCount: seeds,
        attemptsPerSeed: attempts,
        successCount: 0,
        successRate: 0,
        minSuccessRate: minSuccessRate,
        allPassed: false,
        seeds: []
      )
      try writeSweepSummary(summary, to: artifactRoot)
      print("[harness-sweep] artifacts path=\(artifactRoot.path)")
      throw ExitCode.failure
    }

    var seedEntries: [CheckTrainingHarnessSeedEntry] = []
    let initialSourceCheckpointURL = sourceCheckpointURL(from: sourceCheckpointPath)
    let harnessGateService = ReferenceQuadrotorTrainingHarnessGateService()
    for seedIndex in 0..<seeds {
      let seedBase = mlxSeed + UInt64(seedIndex * attempts * max(selectedTasks.count, 1))
      var probeEntries: [CheckTrainingHarnessProbeEntry] = []
      var acceptedTasks: [String: Int] = [:]

      for (taskIndex, task) in selectedTasks.enumerated() {
        var currentSourceCheckpointURL = initialSourceCheckpointURL
        var recoveryDatasetURLs: [URL] = []
        for attempt in 1...attempts {
          let attemptSeed = seedBase + UInt64(taskIndex * attempts + attempt - 1)
          let attemptRoot =
            artifactRoot
            .appendingPathComponent("seed-\(seedBase)", isDirectory: true)
            .appendingPathComponent(task.rawValue, isDirectory: true)
            .appendingPathComponent("attempt-\(attempt)", isDirectory: true)
          let result = try await runCLIManasProbe(
            task: task,
            tier: tier,
            cutPeriodSteps: cutPeriodSteps,
            model: model,
            sourceCheckpointURL: currentSourceCheckpointURL,
            artifactRoot: attemptRoot,
            iterations: 1,
            sequenceLength: sequenceLength,
            epochs: epochs,
            learningRate: learningRate,
            maxBatches: maxBatches,
            workers: 1,
            minDelta: 0,
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverScale: hoverScale,
            useAux: false,
            useQualityGating: !noQualityGate,
            mlxSeed: attemptSeed,
            additionalDatasetURLs: recoveryDatasetURLs,
            additionalDatasetRepeatCount: recoveryRepeat,
            printEvents: false
          )
          let repairSourceCheckpointURL = harnessGateService.repairSourceCheckpointURL(
            result: result)
          currentSourceCheckpointURL = repairSourceCheckpointURL
          if let recoveryDatasetURL = harnessGateService.acceptedRecoveryDatasetURL(result: result)
          {
            recoveryDatasetURLs.append(recoveryDatasetURL)
          }
          let artifacts = try KuyuCLITrainingArtifactReader().validatedProbeArtifacts(
            in: attemptRoot)
          let taskSolved = harnessGateService.taskSolved(result: result)
          let harnessSatisfied = harnessGateService.satisfied(result: result)
          let preRegressionGateReport = harnessGateService.report(
            result: result,
            requireTaskSolved: requireTaskSolved,
            postRegression: nil
          )
          let preRegressionDecision = try harnessGateService.attemptDecision(
            task: task.rawValue,
            attempt: attempt,
            gateReport: preRegressionGateReport
          )
          let postRegressionEntry: ReferenceQuadrotorPostTrainingRegressionEntry?
          if preRegressionDecision.accepted, postRegression {
            let checkpointURL = selectedCandidateCheckpointURL(result.comparison)
            if let checkpointURL {
              let regressionRoot = attemptRoot.appendingPathComponent(
                "post-regression", isDirectory: true)
              _ = try await runKuyuRegression(
                controller: .manasMLX,
                snapshotURL: checkpointURL,
                tier: tier,
                cutPeriodSteps: cutPeriodSteps,
                tasks: [simulationTaskMode(from: task)],
                suites: selectedPostRegressionSuites,
                episodes: postRegressionEpisodes,
                workers: 1,
                maxSteps: nil,
                maxWallTime: nil,
                model: model,
                artifactRoot: regressionRoot,
                kp: kp,
                kd: kd,
                yawDamping: yawDamping,
                hoverScale: hoverScale,
                failOnTruncation: postRegressionFailOnTruncation,
                minimumRewardAverage: postRegressionMinRewardAverage,
                useQualityGating: !noQualityGate
              )
              let validatedRegression = try ReferenceQuadrotorRegressionArtifactLoader()
                .loadSummary(from: regressionRoot)
              postRegressionEntry = harnessGateService.postRegressionEntry(
                regression: validatedRegression,
                artifactPath: regressionRoot.path,
                minimumRewardAverage: validatedRegression.gateReport.minimumRewardAverage
              )
              print(
                "[harness-sweep] seed=\(seedBase) task=\(task.rawValue) attempt=\(attempt) postRegression=\(validatedRegression.allPassed)"
              )
            } else {
              postRegressionEntry = try harnessGateService.missingCheckpointPostRegressionEntry(
                task: task.rawValue,
                minimumRewardAverageOverride: postRegressionMinRewardAverage
              )
            }
          } else {
            postRegressionEntry = nil
          }
          let gateReport = harnessGateService.report(
            result: result,
            requireTaskSolved: requireTaskSolved,
            postRegression: postRegressionEntry
          )
          let attemptDecision = try harnessGateService.attemptDecision(
            task: task.rawValue,
            attempt: attempt,
            gateReport: gateReport
          )
          let entry = CheckTrainingHarnessProbeEntry(
            task: task.rawValue,
            attempt: attempt,
            accepted: attemptDecision.accepted,
            artifactPath: attemptRoot.path,
            terminalState: result.manifest.terminalState.rawValue,
            trainingCheckpoint: result.comparison.checkpointDecision.rawValue,
            probeCheckpoint: result.probeCheckpointDecision.state.rawValue,
            selectedCheckpointRole: result.comparison.selectedCheckpointRole.rawValue,
            selectedCheckpointPath: result.comparison.selectedCheckpointURL?.path,
            repairSourceCheckpointPath: repairSourceCheckpointURL?.path,
            reloadSucceeded: result.comparison.reloadSucceeded,
            teacherScore: result.comparison.teacherScore,
            initialScore: result.comparison.initialScore,
            trainedScore: result.comparison.trainedScore,
            scoreDelta: result.comparison.scoreDelta,
            policySatisfied: result.comparison.policySatisfied,
            harnessSatisfied: harnessSatisfied,
            taskSolved: taskSolved,
            trainedFailureReasons: result.trained?.diagnostics.failureReasons ?? [],
            trainedAverageDriveActivation: result.trained?.diagnostics.averageDriveActivation,
            teacherAverageDriveActivation: result.teacher.diagnostics.averageDriveActivation,
            trainedAverageDriveActivationByIndex: result.trained?.diagnostics
              .averageDriveActivationByIndex,
            teacherAverageDriveActivationByIndex: result.teacher.diagnostics
              .averageDriveActivationByIndex,
            trainedAverageMotorFinalOutputByIndex: result.trained?.diagnostics
              .averageMotorFinalOutputByIndex,
            trainedFinalAltitudeZ: result.trained?.diagnostics.finalAltitudeZ,
            trainedFinalVerticalVelocityZ: result.trained?.diagnostics.finalVerticalVelocityZ,
            metricsCount: artifacts.training.metrics.count,
            recoveryRelabelAttempted: result.recoveryRelabelStatus.attempted,
            recoveryRelabelDatasetPath: result.recoveryRelabelStatus.datasetDirectory?.path,
            recoveryRelabelEntryCount: result.recoveryRelabelStatus.report?.relabeledEntryCount,
            recoveryRelabelCutStepCount: result.recoveryRelabelStatus.report?.relabeledCutStepCount,
            gateReport: gateReport,
            postRegression: postRegressionEntry
          )
          probeEntries.append(entry)
          print(
            "[harness-sweep] seed=\(seedBase) task=\(task.rawValue) attempt=\(attempt) mlxSeed=\(attemptSeed) selected=\(entry.selectedCheckpointRole) repairSource=\(entry.repairSourceCheckpointPath ?? "n/a") recoveryDatasets=\(recoveryDatasetURLs.count) gateAccepted=\(attemptDecision.accepted) gateReasons=\(attemptDecision.rejectionReasons.joined(separator: "|")) harnessSatisfied=\(harnessSatisfied) taskSolved=\(taskSolved) postRegression=\(postRegressionEntry?.allPassed.description ?? "skipped") scoreDelta=\(formatOptional(result.comparison.scoreDelta))"
          )
          if attemptDecision.accepted {
            acceptedTasks[attemptDecision.task] = attemptDecision.attempt
            break
          }
        }
      }

      let successful = try harnessGateService.sweepSeedSuccessful(
        acceptedAttempts: acceptedTasks,
        requiredTasks: selectedTaskNames
      )
      let lastProbe = probeEntries.last
      seedEntries.append(
        CheckTrainingHarnessSeedEntry(
          seedBase: seedBase,
          successful: successful,
          acceptedAttempts: acceptedTasks,
          finalScoreDelta: lastProbe?.scoreDelta,
          finalTrainedScore: lastProbe?.trainedScore,
          finalFailureReasons: lastProbe?.trainedFailureReasons ?? [],
          probes: probeEntries
        )
      )
    }

    let sweepReport = try harnessGateService.sweepReport(
      acceptedAttemptsBySeed: seedEntries.map(\.acceptedAttempts),
      requiredTasks: selectedTaskNames,
      minimumSuccessRate: minSuccessRate
    )
    let summary = CheckTrainingHarnessSweepSummary(
      artifactRoot: artifactRoot.path,
      startedAt: Date(),
      environmentReady: true,
      requirement: requirementName,
      tasks: selectedTaskNames,
      seedCount: seeds,
      attemptsPerSeed: attempts,
      successCount: sweepReport.successCount,
      successRate: sweepReport.successRate,
      minSuccessRate: minSuccessRate,
      allPassed: sweepReport.allPassed,
      seeds: seedEntries
    )
    try writeSweepSummary(summary, to: artifactRoot)
    print("[harness-sweep] artifacts path=\(artifactRoot.path)")
    print(
      "[harness-sweep] successCount=\(sweepReport.successCount)/\(seeds) successRate=\(String(format: "%.3f", sweepReport.successRate)) requirement=\(requirementName) allPassed=\(sweepReport.allPassed)"
    )
    if !sweepReport.allPassed {
      throw ExitCode.failure
    }
  }

  private var requirementName: String {
    requireTaskSolved ? "taskSolved" : "harnessSatisfied"
  }

  private func writeSweepSummary(_ summary: CheckTrainingHarnessSweepSummary, to artifactRoot: URL)
    throws
  {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(summary).write(
      to: artifactRoot.appendingPathComponent("training-harness-sweep-summary.json"),
      options: [.atomic]
    )
  }

  private func formatOptional(_ value: Double?) -> String {
    guard let value else { return "n/a" }
    return String(format: "%.3f", value)
  }
}

struct CheckKuyuRegression: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check-kuyu-regression",
    abstract: "Run Kuyu environment and M2 rollout regression checks."
  )

  @Option(help: "Controller to validate: activeAltitudeHold, sensorBaseline, or manasMLX.")
  var controller: ControllerChoice = .activeAltitudeHold

  @Option(help: "Determinism tier: tier0, tier1, tier2.")
  var tier: TierChoice = .tier1

  @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
  var cutPeriodSteps: UInt64 = 2

  @Option(help: "Comma-separated environment task list: attitude,lift,singleLift.")
  var tasks: String = "attitude,lift,singleLift"

  @Option(help: "Comma-separated M2 suite list: 6,7,8.")
  var suites: String = "6,7,8"

  @Option(help: "Episodes per M2 suite track.")
  var episodes: Int = 1

  @Option(help: "Worker count for rollout regression.")
  var workers: Int = 1

  @Option(
    name: .customLong("max-steps"),
    help: "Maximum steps per M2 rollout episode. Omit for full scenario duration.")
  var maxSteps: Int?

  @Option(
    name: .customLong("max-wall-time"),
    help: "Maximum wall-clock seconds per M2 rollout episode. Omit for no wall-time limit.")
  var maxWallTime: Double?

  @Option(help: "Robot manifest path.")
  var model: String = ""

  @Option(
    help:
      "ManasMLX model snapshot directory containing model.json/core.safetensors/reflex.safetensors."
  )
  var snapshot: String = ""

  @Option(
    name: .customLong("artifact-root"), help: "Directory where regression artifacts are written.")
  var artifactRootPath: String?

  @Option(help: "kp gain for baseline controller.")
  var kp: Double = 2.0

  @Option(help: "kd gain for baseline controller.")
  var kd: Double = 0.25

  @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
  var yawDamping: Double = 0.2

  @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
  var hoverScale: Double = 1.0

  @Flag(
    name: .customLong("fail-on-truncation"),
    help: "Treat max-step truncation as a regression failure.")
  var failOnTruncation: Bool = false

  @Option(
    name: .customLong("min-reward-average"),
    help: "Override the task default minimum reward average required for every rollout track.")
  var minimumRewardAverage: Double?

  @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for ManasMLX rollout.")
  var noQualityGate: Bool = false

  @MainActor
  mutating func run() async throws {
    let selectedController = controllerSelection(from: controller)
    guard episodes > 0 else {
      throw ValidationError("--episodes must be greater than 0.")
    }
    guard workers > 0 else {
      throw ValidationError("--workers must be greater than 0.")
    }
    if let maxSteps, maxSteps <= 0 {
      throw ValidationError("--max-steps must be greater than 0 when specified.")
    }
    if let maxWallTime, !(maxWallTime.isFinite && maxWallTime > 0) {
      throw ValidationError("--max-wall-time must be greater than 0 when specified.")
    }
    if let minimumRewardAverage, !minimumRewardAverage.isFinite {
      throw ValidationError("--min-reward-average must be finite when specified.")
    }

    let selectedTasks = try parseProbeTasks(tasks).map(simulationTaskMode(from:))
    let selectedSuites = try parseRegressionSuites(suites)
    let artifactRoot: URL
    if let artifactRootPath,
      !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
    } else {
      artifactRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-regression-\(UUID().uuidString)", isDirectory: true)
    }
    let snapshotURL = try regressionSnapshotURL(snapshot, controller: selectedController)
    _ = try await runKuyuRegression(
      controller: selectedController,
      snapshotURL: snapshotURL,
      tier: tier,
      cutPeriodSteps: cutPeriodSteps,
      tasks: selectedTasks,
      suites: selectedSuites,
      episodes: episodes,
      workers: workers,
      maxSteps: maxSteps,
      maxWallTime: maxWallTime,
      model: model,
      artifactRoot: artifactRoot,
      kp: kp,
      kd: kd,
      yawDamping: yawDamping,
      hoverScale: hoverScale,
      failOnTruncation: failOnTruncation,
      minimumRewardAverage: minimumRewardAverage,
      useQualityGating: !noQualityGate
    )
    let validatedSummary = try ReferenceQuadrotorRegressionArtifactLoader().loadSummary(
      from: artifactRoot)
    print("[regression] artifacts path=\(artifactRoot.path)")
    print(
      "[regression] environmentReady=\(validatedSummary.environmentReady) rolloutPassed=\(validatedSummary.rolloutPassed) gateAccepted=\(validatedSummary.gateReport.accepted) reasons=\(validatedSummary.gateReport.reasons.joined(separator: "|")) allPassed=\(validatedSummary.allPassed)"
    )
    if !validatedSummary.allPassed {
      throw ExitCode.failure
    }
  }

}

struct CheckKuyuRegressionMatrix: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check-kuyu-regression-matrix",
    abstract: "Run a task/controller matrix of Kuyu regression checks."
  )

  @Option(help: "Comma-separated controller list: activeAltitudeHold,sensorBaseline,manasMLX.")
  var controllers: String = "activeAltitudeHold"

  @Option(help: "Comma-separated task list: lift,singleLift.")
  var tasks: String = "lift,singleLift"

  @Option(help: "Comma-separated M2 suite list: 6,7,8.")
  var suites: String = "6"

  @Option(help: "Episodes per matrix cell.")
  var episodes: Int = 1

  @Option(help: "Worker count for rollout regression.")
  var workers: Int = 1

  @Option(help: "Determinism tier: tier0, tier1, tier2.")
  var tier: TierChoice = .tier1

  @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
  var cutPeriodSteps: UInt64 = 2

  @Option(help: "Robot manifest path.")
  var model: String = ""

  @Option(help: "ManasMLX model snapshot directory.")
  var snapshot: String = ""

  @Option(name: .customLong("artifact-root"), help: "Directory where matrix artifacts are written.")
  var artifactRootPath: String?

  @Option(
    name: .customLong("min-reward-average"), help: "Override task default minimum reward average.")
  var minimumRewardAverage: Double?

  @Flag(
    name: .customLong("fail-on-truncation"),
    help: "Treat max-step truncation as a regression failure.")
  var failOnTruncation: Bool = false

  @MainActor
  mutating func run() async throws {
    guard episodes > 0 else {
      throw ValidationError("--episodes must be greater than 0.")
    }
    guard workers > 0 else {
      throw ValidationError("--workers must be greater than 0.")
    }
    if let minimumRewardAverage, !minimumRewardAverage.isFinite {
      throw ValidationError("--min-reward-average must be finite when specified.")
    }

    let selectedControllers = try parseRegressionControllers(controllers)
    let selectedTasks = try parseProbeTasks(tasks).map(simulationTaskMode(from:))
    let selectedSuites = try parseRegressionSuites(suites)
    let artifactRoot: URL
    if let artifactRootPath,
      !artifactRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
    } else {
      artifactRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-regression-matrix-\(UUID().uuidString)", isDirectory: true)
    }
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)

    let matrixSummaryService = ReferenceQuadrotorRegressionMatrixSummaryService()
    var entries: [ReferenceQuadrotorRegressionMatrixEntry] = []
    for controller in selectedControllers {
      let selectedController = controllerSelection(from: controller)
      for task in selectedTasks {
        let taskName = rolloutTaskChoice(from: task).rawValue
        let cellRoot =
          artifactRoot
          .appendingPathComponent(controller.rawValue, isDirectory: true)
          .appendingPathComponent(taskName, isDirectory: true)
        do {
          let snapshotURL = try regressionSnapshotURL(snapshot, controller: selectedController)
          _ = try await runKuyuRegression(
            controller: selectedController,
            snapshotURL: snapshotURL,
            tier: tier,
            cutPeriodSteps: cutPeriodSteps,
            tasks: [task],
            suites: selectedSuites,
            episodes: episodes,
            workers: workers,
            maxSteps: nil,
            maxWallTime: nil,
            model: model,
            artifactRoot: cellRoot,
            kp: 2.0,
            kd: 0.25,
            yawDamping: 0.2,
            hoverScale: 1.0,
            failOnTruncation: failOnTruncation,
            minimumRewardAverage: minimumRewardAverage,
            useQualityGating: true
          )
          let regressionSummary = try ReferenceQuadrotorRegressionArtifactLoader().loadSummary(
            from: cellRoot)
          let entry = matrixSummaryService.entry(
            controller: controller.rawValue,
            task: taskName,
            artifactPath: cellRoot.path,
            summary: regressionSummary
          )
          entries.append(entry)
          print(
            "[regression-matrix] controller=\(controller.rawValue) task=\(taskName) accepted=\(entry.accepted) artifact=\(cellRoot.path)"
          )
        } catch {
          let entry = matrixSummaryService.failedEntry(
            controller: controller.rawValue,
            task: taskName,
            artifactPath: cellRoot.path,
            reason: String(describing: error)
          )
          entries.append(entry)
          print(
            "[regression-matrix] controller=\(controller.rawValue) task=\(taskName) accepted=\(entry.accepted) reason=\(error)"
          )
        }
      }
    }

    let summary = matrixSummaryService.makeSummary(
      request: ReferenceQuadrotorRegressionMatrixSummaryRequest(
        artifactRoot: artifactRoot.path,
        controllers: selectedControllers.map(\.rawValue),
        tasks: selectedTasks.map { rolloutTaskChoice(from: $0).rawValue },
        suites: selectedSuites,
        episodes: episodes,
        entries: entries
      )
    )
    try writeRegressionMatrixSummary(summary, to: artifactRoot)
    print("[regression-matrix] artifacts path=\(artifactRoot.path) allPassed=\(summary.allPassed)")
    if !summary.allPassed {
      throw ExitCode.failure
    }
  }
}

/// Staged self-verification harness. Runs a sequence of checks with per-stage CLI
/// output so the system can be validated incrementally without the GUI or a trained
/// checkpoint. Exits non-zero if any check fails.
struct Verify: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "verify",
    abstract:
      "Staged self-verification: MLX preflight, environment readiness, Tier-0 determinism, and A1 conformance suites (0–5), each reported as it runs."
  )

  @Option(help: "Determinism tier: tier0, tier1, tier2.")
  var tier: TierChoice = .tier0

  @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
  var cutPeriodSteps: UInt64 = 2

  @Option(help: "Robot manifest path (optional; empty uses the reference baseline).")
  var model: String = ""

  @Option(help: "Scenarios per A1 suite stage.")
  var episodes: Int = 1

  @Option(
    name: .customLong("max-steps"),
    help:
      "Maximum steps per rollout episode. Omit for the full scenario duration (needed to reach mid-run swaps)."
  )
  var maxSteps: Int?

  @Option(name: .customLong("artifact-root"), help: "Directory for verification artifacts.")
  var artifactRootPath: String = "/tmp/kuyu-verify"

  @Flag(
    name: .customLong("skip-mlx"),
    help: "Skip the MLX runtime preflight stage (pure-physics verification only).")
  var skipMLX: Bool = false

  @Option(help: "kp gain for the baseline controller.")
  var kp: Double = 2.0
  @Option(help: "kd gain for the baseline controller.")
  var kd: Double = 0.25
  @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for the baseline controller.")
  var yawDamping: Double = 0.2
  @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
  var hoverScale: Double = 1.0

  mutating func run() async throws {
    let artifactRoot = URL(fileURLWithPath: artifactRootPath, isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)

    let determinism = try makeDeterminism(tier: tier)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
    let gains = try ImuRateDampingCutGains(
      kp: kp, kd: kd, yawDamping: yawDamping, hoverThrustScale: hoverScale)
    let loadedRobot = try loadLoadedRobot(modelPath: model)
    let parameters = try makeRolloutParameters(
      task: .attitude, loadedRobot: loadedRobot, hoverThrustScale: hoverScale)
    let limits = try RolloutRunner.Limits.validated(
      maxStepsPerEpisode: maxSteps, maxWallTimeSeconds: nil)

    func baselineRollout(_ definitions: [ReferenceQuadrotorScenarioDefinition]) async throws
      -> RolloutSummary
    {
      let runner = RolloutRunner(
        parameters: parameters,
        schedule: schedule,
        determinism: determinism,
        hoverThrustScale: hoverScale,
        loadedRobot: loadedRobot,
        motorNerveRateLimitPerSecond: 100.0,
        motorNerveSmoothingTimeConstant: nil,
        limits: limits
      )
      let policy = KuyAtt1BaselinePolicyFactory(
        parameters: parameters, gains: gains, mode: .teacher)
      let episodeResults = try await runner.run(definitions: definitions, policyFactory: policy)
      return RolloutSummary(episodes: episodeResults)
    }

    var failures = 0
    let stageCount = skipMLX ? 3 : 4
    var stageIndex = 0
    func stage(_ name: String) {
      stageIndex += 1
      print("[verify \(stageIndex)/\(stageCount)] \(name)")
    }
    func pass(_ detail: String) { print("[verify]   PASS — \(detail)") }
    func fail(_ detail: String) {
      failures += 1
      print("[verify]   FAIL — \(detail)")
    }

    // Stage 1: MLX runtime preflight.
    if !skipMLX {
      stage("MLX runtime preflight")
      do {
        let report = try ManasMLXRuntimeReadinessService().report(
          for: ManasMLXRuntimeReadinessRequest(robotManifestPath: model)
        )
        if report.mlxRuntimeReady {
          pass("MLX/Metal runtime ready (robotManifestLoaded=\(report.robotManifestLoaded))")
        } else {
          fail("MLX runtime not ready")
        }
      } catch {
        fail("MLX preflight threw: \(error)")
      }
    }

    // Stage 2: environment readiness for the attitude task (teacher baseline).
    stage("Environment readiness (attitude)")
    do {
      let report = try await ReferenceQuadrotorEnvironmentReadinessChecker().check(
        tasks: [.attitude],
        controller: .teacherActiveAltitudeHold,
        parameters: parameters,
        schedule: schedule,
        determinism: determinism,
        gains: gains,
        robotManifestPath: model,
        embodiment: loadedRobot?.embodiment,
        artifactRoot: artifactRoot.appendingPathComponent(
          "environment-readiness", isDirectory: true)
      )
      for task in report.tasks {
        print(
          "[verify]   env task=\(task.task) ready=\(task.ready) score=\(String(format: "%.3f", task.score))"
        )
      }
      if report.allReady {
        pass("all attitude environments ready")
      } else {
        fail("environment not ready")
      }
    } catch {
      fail("readiness threw: \(error)")
    }

    // Stage 3: Tier-0 determinism — A1 Suite-1 run twice must be bit-exact.
    stage("Tier-0 determinism (A1 Suite-1, bit-exact replay)")
    do {
      let definitions = try makeRolloutDefinitions(task: .attitude, suite: 1, episodes: episodes)
      let first = try await baselineRollout(definitions)
      let second = try await baselineRollout(definitions)
      if first.rewardSum == second.rewardSum {
        pass("identical rewardSum across two runs (\(String(format: "%.6f", first.rewardSum)))")
      } else {
        fail("rewardSum differs: \(first.rewardSum) vs \(second.rewardSum)")
      }
    } catch {
      fail("determinism stage threw: \(error)")
    }

    // Stage 4: A1 conformance suites 0…5 — verify stressor injection and that each runs.
    stage("A1 conformance suites (Suite-0 … Suite-5)")
    for level in A1ConformanceSuite.Level.allCases {
      do {
        let definitions = try makeRolloutDefinitions(
          task: .attitude, suite: level.rawValue, episodes: episodes)
        let swapCount = definitions.reduce(0) { $0 + $1.swapEvents.count }
        let hfCount = definitions.reduce(0) { $0 + $1.hfEvents.count }
        // Warmup must inject no stress; every other suite must inject at least one event.
        let injectionOK =
          level == .warmup
          ? (swapCount + hfCount == 0)
          : (swapCount + hfCount > 0)
        let summary = try await baselineRollout(definitions)
        if !definitions.isEmpty && injectionOK {
          pass(
            "\(level.suiteID) scenarios=\(definitions.count) swaps=\(swapCount) hf=\(hfCount) ran=\(summary.episodeCount) failures=\(summary.failureCount)"
          )
        } else {
          fail(
            "\(level.suiteID) scenarios=\(definitions.count) swaps=\(swapCount) hf=\(hfCount) (injection mismatch)"
          )
        }
      } catch {
        fail("\(level.suiteID) threw: \(error)")
      }
    }

    print("")
    if failures == 0 {
      print("[verify] ALL CHECKS PASSED")
    } else {
      print("[verify] \(failures) CHECK(S) FAILED")
      throw ExitCode.failure
    }
  }
}

func makeDeterminism(tier: TierChoice) throws -> DeterminismConfig {
  try learningCampaignTier(from: tier).referenceQuadrotorDeterminismConfig()
}

func learningCampaignTier(from tier: TierChoice) -> LearningCampaignTier {
  switch tier {
  case .tier0:
    return .tier0
  case .tier1:
    return .tier1
  case .tier2:
    return .tier2
  }
}

func learningCampaignRolloutTask(from task: RolloutTaskChoice) -> LearningCampaignRolloutTask {
  switch task {
  case .attitude:
    return .attitude
  case .lift:
    return .lift
  case .singleLift:
    return .singleLift
  }
}

func loadParameters(modelPath: String) throws -> ReferenceQuadrotorParameters {
  try ReferenceQuadrotorParameterResolutionService().resolvedParameters(modelPath: modelPath)
}

func loadEmbodiment(modelPath: String) throws -> EmbodimentContract? {
  let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }

  let loader = KuyuModelLoader()
  let embodiment = try loader.loadRobot(path: trimmed)
  return embodiment.embodiment
}

func loadLoadedRobot(modelPath: String) throws -> LoadedKuyuRobot? {
  let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }

  let loader = KuyuModelLoader()
  return try loader.loadRobot(path: trimmed)
}

private func score(from summary: ValidationSummary) -> Double {
  var score = summary.suitePassed ? 1.0 : 0.0
  if let worstOvershoot = summary.aggregate.worstOvershootDegrees {
    score -= min(1.0, worstOvershoot / 90.0) * 0.4
  }
  if let recovery = summary.aggregate.averageRecoveryTime {
    score -= min(1.0, recovery / 5.0) * 0.3
  }
  if let hf = summary.aggregate.averageHfStabilityScore {
    score += max(0.0, min(hf, 1.0)) * 0.2
  }
  return score
}

private func printSummary(output: KuyAtt1RunOutput) {
  let summary = output.summary
  let aggregate = summary.aggregate
  let overshoot = aggregate.worstOvershootDegrees.map { String(format: "%.2f", $0) } ?? "n/a"
  let recovery = aggregate.averageRecoveryTime.map { String(format: "%.2f", $0) } ?? "n/a"
  let hf = aggregate.averageHfStabilityScore.map { String(format: "%.2f", $0) } ?? "n/a"
  print(
    "passed=\(summary.suitePassed) scenarios=\(summary.evaluations.count) overshoot=\(overshoot) recovery=\(recovery) hf=\(hf)"
  )
}

func makeRolloutDefinitions(
  task: RolloutTaskChoice,
  suite: Int?,
  episodes: Int,
  useTrainingSuite: Bool = false
) throws -> [ReferenceQuadrotorScenarioDefinition] {
  try ReferenceQuadrotorRolloutScenarioDefinitionFactory().scenarios(
    task: learningCampaignRolloutTask(from: task),
    suite: suite,
    episodes: episodes,
    useTrainingSuite: useTrainingSuite
  )
}

func simulationTaskMode(from task: RolloutTaskChoice) -> SimulationTaskMode {
  switch task {
  case .attitude:
    return .attitude
  case .lift:
    return .lift
  case .singleLift:
    return .singleLift
  }
}

private func simulationTaskMode(from task: CTBRCheckpointTaskChoice) -> SimulationTaskMode {
  switch task {
  case .attitude:
    return .attitude
  case .lift:
    return .lift
  }
}

func controllerSelection(from controller: ControllerChoice) -> ControllerSelection {
  switch controller {
  case .activeAltitudeHold:
    return .teacherActiveAltitudeHold
  case .sensorBaseline:
    return .sensorBaseline
  case .manasMLX:
    return .manasMLX
  }
}

func parseRegressionControllers(_ raw: String) throws -> [ControllerChoice] {
  let values =
    raw
    .split(separator: ",")
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
  guard !values.isEmpty else {
    throw ValidationError("--controllers must include at least one controller.")
  }
  return try values.map { value in
    guard let controller = ControllerChoice(rawValue: value) else {
      throw ValidationError("--controllers contains unsupported controller: \(value)")
    }
    return controller
  }
}

func makeRolloutParameters(
  task: RolloutTaskChoice,
  loadedRobot: LoadedKuyuRobot? = nil,
  hoverThrustScale: Double = 1.0
) throws -> ReferenceQuadrotorParameters {
  let taskMode = simulationTaskMode(from: task)
  do {
    return try ReferenceQuadrotorParameterResolutionService().parameters(
      taskMode: taskMode,
      hoverThrustScale: hoverThrustScale,
      loadedRobot: loadedRobot
    )
  } catch ReferenceQuadrotorParameterResolutionError.invalidHoverScale {
    throw ValidationError("--hover-scale must be finite and greater than 0.")
  } catch {
    throw error
  }
}

func safePathComponent(_ raw: String) -> String {
  let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.="))
  let scalars = raw.unicodeScalars.map { scalar in
    allowed.contains(scalar) ? Character(scalar) : "_"
  }
  return String(scalars)
}

func parseDescendingVector(_ raw: String, optionName: String = "--descending") throws -> [Double]? {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    return nil
  }

  let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
  guard !parts.isEmpty else {
    return nil
  }

  var vector: [Double] = []
  vector.reserveCapacity(parts.count)
  for part in parts {
    guard !part.isEmpty else {
      throw ValidationError("Invalid \(optionName) value ''. Use comma-separated finite numbers.")
    }
    guard let value = Double(part), value.isFinite else {
      throw ValidationError(
        "Invalid \(optionName) value '\(part)'. Use comma-separated finite numbers.")
    }
    vector.append(value)
  }
  return vector
}

func parseDescendingProgram(_ raw: String) throws -> DescendingIntentProgram? {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    return nil
  }

  let frameSpecs = trimmed.split(separator: ";", omittingEmptySubsequences: false)
  var keyframes: [DescendingIntentProgram.Keyframe] = []
  keyframes.reserveCapacity(frameSpecs.count)

  for frameSpec in frameSpecs {
    let entry = frameSpec.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !entry.isEmpty else {
      throw ValidationError("Invalid --descending-program frame ''. Use 'time:values;time:values'.")
    }
    guard let separator = entry.firstIndex(of: ":") else {
      throw ValidationError("Invalid --descending-program frame '\(entry)'. Missing ':'.")
    }

    let timeToken = String(entry[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
    let valuesToken = String(entry[entry.index(after: separator)...]).trimmingCharacters(
      in: .whitespacesAndNewlines)
    guard let time = Double(timeToken), time.isFinite else {
      throw ValidationError("Invalid --descending-program time '\(timeToken)'.")
    }
    guard let values = try parseDescendingVector(valuesToken, optionName: "--descending-program")
    else {
      throw ValidationError("Invalid --descending-program values '\(valuesToken)'.")
    }

    do {
      let frame = try DescendingIntentProgram.Keyframe(time: time, values: values)
      keyframes.append(frame)
    } catch {
      throw ValidationError("Invalid --descending-program frame '\(entry)': \(error)")
    }
  }

  do {
    return try DescendingIntentProgram(keyframes: keyframes)
  } catch {
    throw ValidationError("Invalid --descending-program: \(error)")
  }
}
