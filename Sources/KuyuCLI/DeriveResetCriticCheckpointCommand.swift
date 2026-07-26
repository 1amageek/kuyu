import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuTraining

struct DeriveResetCriticCheckpoint: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "derive-reset-critic-checkpoint",
    abstract:
      "Derive a checkpoint whose actor is identical to the source and whose reward critic is returned to fresh initialization."
  )

  @Option(name: .customLong("source-checkpoint"), help: "Source checkpoint directory.")
  var sourceCheckpoint: String

  @Option(
    name: .customLong("output-checkpoint"), help: "Output checkpoint directory (must not exist).")
  var outputCheckpoint: String

  @Option(
    name: .customLong("critic-seed"),
    help:
      "Seed for the fresh critic initialization. Record it: it is the only input that makes the derivation reproducible."
  )
  var criticSeed: UInt64

  @Option(name: .customLong("name"), help: "Checkpoint name recorded in the manifest.")
  var checkpointName: String = "reset-critic-derived"

  mutating func run() throws {
    let service = ManasMLXTemporalReinforcementWarmupService(
      rolloutDatasetLoader: ReferenceQuadrotorTemporalRolloutDatasetLoaderFactory.make()
    )
    try service.deriveResetCriticCheckpoint(
      sourceCheckpointURL: URL(fileURLWithPath: sourceCheckpoint, isDirectory: true)
        .standardizedFileURL,
      outputCheckpointURL: URL(fileURLWithPath: outputCheckpoint, isDirectory: true)
        .standardizedFileURL,
      checkpointName: checkpointName,
      criticInitializationSeed: criticSeed
    )
    print("[derive-reset-critic-checkpoint] wrote \(outputCheckpoint)")
    print("[derive-reset-critic-checkpoint] criticSeed=\(criticSeed) name=\(checkpointName)")
  }
}
