import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuTraining

struct DeriveInterpolatedCheckpoint: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "derive-interpolated-checkpoint",
    abstract:
      "Derive a checkpoint whose parameters linearly interpolate between two checkpoints that share the same policy config and schema contracts."
  )

  @Option(name: .customLong("checkpoint-a"), help: "First source checkpoint directory (factor 0).")
  var checkpointA: String

  @Option(name: .customLong("checkpoint-b"), help: "Second source checkpoint directory (factor 1).")
  var checkpointB: String

  @Option(
    name: .customLong("factor"),
    help: "Interpolation factor in (0, 1): weight of checkpoint B.")
  var factor: Double

  @Option(name: .customLong("output-checkpoint"), help: "Output checkpoint directory (must not exist).")
  var outputCheckpoint: String

  @Option(name: .customLong("name"), help: "Checkpoint name recorded in the manifest.")
  var checkpointName: String = "interpolated-derived"

  mutating func run() throws {
    let service = ManasMLXTemporalReinforcementWarmupService(
      rolloutDatasetLoader: ReferenceQuadrotorTemporalRolloutDatasetLoaderFactory.make()
    )
    try service.deriveInterpolatedCheckpoint(
      firstCheckpointURL: URL(fileURLWithPath: checkpointA, isDirectory: true)
        .standardizedFileURL,
      secondCheckpointURL: URL(fileURLWithPath: checkpointB, isDirectory: true)
        .standardizedFileURL,
      interpolationFactor: factor,
      outputCheckpointURL: URL(fileURLWithPath: outputCheckpoint, isDirectory: true)
        .standardizedFileURL,
      checkpointName: checkpointName
    )
    print("[derive-interpolated-checkpoint] wrote \(outputCheckpoint)")
    print("[derive-interpolated-checkpoint] factor=\(factor) (weight of checkpoint B)")
  }
}
