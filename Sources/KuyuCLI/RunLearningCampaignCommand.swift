import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuTraining
import KuyuUI

struct RunLearningCampaign: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run-learning-campaign",
    abstract: "Run a typed Swift learning campaign over one or more seeds."
  )

  @Option(help: "Task to optimize: attitude, lift, or singleLift.")
  var task: LearningCampaignTask = .attitude

  @Option(
    name: .customLong("source-checkpoint"), help: "Task-specific source checkpoint directory.")
  var sourceCheckpoint: String?

  @Option(
    name: .customLong("continue-from-artifact-root"),
    help: "Previous learning campaign artifact root to continue from.")
  var continueFromArtifactRoot: String?

  @Flag(
    name: .customLong("resume"),
    help:
      "Resume an interrupted campaign in place from each seed's last committed generation checkpoint."
  )
  var resume: Bool = false

  @Option(
    name: .customLong("resume-from-generation"),
    help: "When resuming, roll back to this generation index instead of the highest committed one.")
  var resumeFromGeneration: Int?

  @Option(
    name: .customLong("artifact-root"), help: "Directory where campaign artifacts are written.")
  var artifactRootPath: String

  @Option(help: "Comma-separated explicit campaign seed values.")
  var seeds: String?

  @Option(
    name: .customLong("seed-count"),
    help: "Generate sequential campaign seeds from 1 through this count.")
  var seedCount: Int = 1

  @Option(help: "Population size per seed.")
  var population: Int = 100

  @Option(
    help:
      "Maximum generation budget per seed. Normal completion is convergence or plateau early stopping."
  )
  var generations: Int = 1_000

  @Option(name: .customLong("elite-count"), help: "Number of candidates selected as parents.")
  var eliteCount: Int = 10

  @Option(help: "Worker count for rollout regression.")
  var workers: Int = 1

  @Option(
    name: .customLong("candidate-evaluation-concurrency"),
    help: "Maximum Manas candidate evaluations to run concurrently.")
  var candidateEvaluationConcurrency: Int = 100

  @Flag(
    name: .customLong("no-auto-parallelism"),
    help: "Disable machine-optimized population and evaluation concurrency.")
  var noAutoParallelism: Bool = false

  @Option(help: "Comma-separated M2 suite list: 6,7,8.")
  var suites: String = "6"

  @Option(help: "Episodes per candidate regression.")
  var episodes: Int = 1

  @Option(
    name: .customLong("screening-control-steps"),
    help: "Maximum control steps per search episode before full acceptance evaluation.")
  var screeningControlSteps: Int = 1_000

  @Option(
    name: .customLong("acceptance-suites"),
    help: "Comma-separated full-physics acceptance suite list.")
  var acceptanceSuites: String = "6,7,8"

  @Option(
    name: .customLong("acceptance-episodes"),
    help: "Full-physics episodes per acceptance suite.")
  var acceptanceEpisodes: Int = 3

  @Option(
    name: .customLong("world-execution"),
    help:
      "Search world execution: auto (task default), accelerated (require tensor world), or cpu (require isolated CPU worlds; measured 6-10x faster at small populations)."
  )
  var worldExecution: LearningCampaignWorldExecution = .auto

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

  @Option(name: .customLong("search-strategy"), help: "Evolution search strategy.")
  var searchStrategy: EvolutionSearchStrategy = .qualityDiversity

  @Option(help: "Candidate variation mode: gaussian or copy.")
  var variation: LearningCampaignVariation = .gaussian

  @Option(
    name: .customLong("min-reward-average"), help: "Override task default minimum reward average.")
  var minimumRewardAverage: Double?

  @Flag(
    name: .customLong("no-reinforcement-warmup"),
    help: "Disable the temporal CTBR PPO warmup before genetic evolution.")
  var noReinforcementWarmup: Bool = false

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
    help: "Optional maximum number of rollout batches used by PPO warmup.")
  var reinforcementWarmupMaxBatches: Int?

  @Option(
    name: .customLong("reinforcement-dual-learning-rate"),
    help:
      "Dual-ascent step size for the Lagrangian safety-cost multiplier (backend default 0.05). Raise it when the observed episode cost stays far above the cost limit while lambda remains near zero."
  )
  var reinforcementDualLearningRate: Double?

  @Option(
    name: .customLong("reinforcement-initial-lambda"),
    help:
      "Initial Lagrangian safety-cost multiplier (backend default 0). The dual state advances only on committed iterations, so set this above zero to apply cost pressure from the first iteration when chaining short runs."
  )
  var reinforcementInitialLambda: Double?

  @Option(
    name: .customLong("reinforcement-dual-cost-limit"),
    help:
      "Safety-cost budget the dual ascends against during training (backend default is the task's terminal budget). Set it inside the range the current policy actually reaches so the constraint gap can change sign, and lower it across segments. It never relaxes the promotion budget."
  )
  var reinforcementDualCostLimit: Double?

  @Option(
    name: .customLong("reinforcement-training-suites"),
    help:
      "Comma-separated A1 suite IDs whose graded scenarios are injected into the RR PPO training distribution at --search-stress-severity (e.g. 2 to train on actuator-swap stress). Requires --search-stress-severity."
  )
  var reinforcementTrainingSuites: String?

  @Flag(
    name: .customLong("observation-motor-feedback"),
    help:
      "Use the 20-channel body-rate observation with achieved per-motor outputs (channels 16-19). Requires a source checkpoint derived onto the 20ch schema via scripts/derive_motor_feedback_checkpoint.py."
  )
  var observationMotorFeedback: Bool = false

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
    name: .customLong("exploration-log-std"),
    help:
      "Declare the fixed exploration log standard deviation of the CTBR gaussian action distribution (default -3.2, sigma about 0.04). The exploration width is stored in the checkpoint, so this value must match the source checkpoint's width; a run that declares a different width is rejected. Write the checkpoint at the desired width to refine with wider exploration."
  )
  var explorationLogStd: Double?

  @Option(
    name: .customLong("acceptance-stress-severity"),
    help:
      "Actuator-swap stress severity in (0, 1] for severity-capable acceptance suites. Required with --absolute-promotion; omit for full-severity capability claims."
  )
  var acceptanceStressSeverity: Double?

  @Flag(
    name: .customLong("absolute-promotion"),
    help:
      "Curriculum-rung promotion: accept the search winner on the absolute gate (full pass rate, zero safety violations, metric floors) without incumbent comparison. Requires --acceptance-stress-severity; final full-severity rungs must omit this flag."
  )
  var absolutePromotion: Bool = false

  @Option(
    name: .customLong("search-stress-severity"),
    help:
      "Actuator-swap stress severity in (0, 1] for severity-capable search suites (A1). Below 1 the severity is stamped into scenario IDs; acceptance always runs at full severity."
  )
  var searchStressSeverity: Double?

  @Option(
    name: .customLong("max-rejected-generations"),
    help:
      "Consecutive gate-rejected generations allowed to keep exploring with ranking-selected parents before the search stops. Default 0 stops at the first rejected generation; exploration never grants elite or acceptance eligibility."
  )
  var maxRejectedGenerations: Int?

  @Option(
    name: .customLong("resource-sample-seconds"),
    help:
      "Resource sample interval recorded in the campaign plan. Use 0 to disable resource samples.")
  var resourceSampleSeconds: Double = 30

  @Option(
    name: .customLong("artifact-retention"), help: "Artifact retention mode: full or compact.")
  var artifactRetention: LearningCampaignArtifactRetentionMode = .compact

  @Option(
    name: .customLong("autonomy-domain"),
    help: "Autonomy domain: automotive, groundRobot, aerialDrone, or manipulator.")
  var autonomyDomain: AutonomousOperationDomain = .aerialDrone

  @Option(
    name: .customLong("reinforcement-artifact"),
    help:
      "Optional accepted RL training-run artifact directory to attach as reinforcement stage evidence."
  )
  var reinforcementArtifactPath: String?

  @Flag(
    name: .customLong("skip-initial-parent-pass"),
    help: "Run starter evolution even when the source checkpoint does not yet pass the task gate.")
  var skipInitialParentPass: Bool = false

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

}
