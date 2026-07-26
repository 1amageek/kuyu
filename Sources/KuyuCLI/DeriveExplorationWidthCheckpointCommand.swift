import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuTraining

struct DeriveExplorationWidthCheckpoint: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "derive-exploration-width-checkpoint",
    abstract:
      "Derive a checkpoint that is parameter-identical to the source and differs only in the fixed exploration width of its gaussian action distribution."
  )

  @Option(name: .customLong("source-checkpoint"), help: "Source checkpoint directory.")
  var sourceCheckpoint: String

  @Option(
    name: .customLong("output-checkpoint"), help: "Output checkpoint directory (must not exist).")
  var outputCheckpoint: String

  @Option(
    name: .customLong("exploration-log-std"),
    help:
      "Fixed exploration log standard deviation for every action channel. PPO's clip bounds the per-iteration action-mean shift at a fixed multiple of this width, so it is the corridor's step-size control: -3.2 (sigma 0.041) permits about 0.1% of action range per iteration, -2.3 (sigma 0.100) about 0.28%."
  )
  var explorationLogStd: Double

  @Option(name: .customLong("name"), help: "Checkpoint name recorded in the manifest.")
  var checkpointName: String = "exploration-width-derived"

  mutating func run() throws {
    guard explorationLogStd.isFinite, explorationLogStd < 0, explorationLogStd >= -5 else {
      throw ValidationError("--exploration-log-std must be finite and in [-5, 0).")
    }
    let service = ManasMLXTemporalReinforcementWarmupService(
      rolloutDatasetLoader: ReferenceQuadrotorTemporalRolloutDatasetLoaderFactory.make()
    )
    try service.deriveExplorationWidthCheckpoint(
      sourceCheckpointURL: URL(fileURLWithPath: sourceCheckpoint, isDirectory: true)
        .standardizedFileURL,
      outputCheckpointURL: URL(fileURLWithPath: outputCheckpoint, isDirectory: true)
        .standardizedFileURL,
      checkpointName: checkpointName,
      baseLogStandardDeviation: explorationLogStd
    )
    let sigma = Foundation.exp(explorationLogStd)
    print("[derive-exploration-width-checkpoint] wrote \(outputCheckpoint)")
    print(
      "[derive-exploration-width-checkpoint] logStd=\(explorationLogStd) sigma=\(sigma)")
  }
}
