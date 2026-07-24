import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuTraining

struct DeriveMotorFeedbackCheckpoint: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "derive-motor-feedback-checkpoint",
    abstract:
      "Derive a body-rate-motor-feedback (20ch) checkpoint from a 16ch source by expanding the actor/critic input projections with zero-initialized columns (function-identical at initialization)."
  )

  @Option(name: .customLong("source-checkpoint"), help: "16ch source checkpoint directory.")
  var sourceCheckpoint: String

  @Option(name: .customLong("output-checkpoint"), help: "Output checkpoint directory (must not exist).")
  var outputCheckpoint: String

  @Option(name: .customLong("name"), help: "Checkpoint name recorded in the manifest.")
  var checkpointName: String = "motor-feedback-derived"

  mutating func run() throws {
    let contract = ReferenceQuadrotorLearningContracts
      .bodyRateMotorFeedbackObservationContract()
    let service = ManasMLXTemporalReinforcementWarmupService(
      rolloutDatasetLoader: ReferenceQuadrotorTemporalRolloutDatasetLoaderFactory.make()
    )
    try service.deriveExpandedObservationCheckpoint(
      sourceCheckpointURL: URL(fileURLWithPath: sourceCheckpoint, isDirectory: true)
        .standardizedFileURL,
      outputCheckpointURL: URL(fileURLWithPath: outputCheckpoint, isDirectory: true)
        .standardizedFileURL,
      checkpointName: checkpointName,
      targetObservationSchemaID: contract.schemaID,
      targetObservationDimension: contract.channelCount
    )
    print("[derive-motor-feedback-checkpoint] wrote \(outputCheckpoint)")
    print("[derive-motor-feedback-checkpoint] schema=\(contract.schemaID) channels=\(contract.channelCount)")
  }
}
