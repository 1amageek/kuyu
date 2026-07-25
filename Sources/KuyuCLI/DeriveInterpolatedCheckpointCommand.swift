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
    help: "Interpolation factor in (0, 1]: weight of checkpoint B.")
  var factor: Double

  @Option(
    name: .customLong("key-prefix"),
    help:
      "Restrict interpolation to parameters whose key starts with this prefix (repeatable); other parameters are copied from checkpoint A.")
  var keyPrefixes: [String] = []

  @Option(
    name: .customLong("column-start"),
    help:
      "First last-axis column (inclusive) to interpolate in the prefixed 2-D parameters; requires --key-prefix. 1-D parameters matching a prefix interpolate fully.")
  var columnStart: Int?

  @Option(
    name: .customLong("column-end"),
    help: "Last-axis column (exclusive) ending the interpolated range; requires --column-start.")
  var columnEnd: Int?

  @Option(name: .customLong("output-checkpoint"), help: "Output checkpoint directory (must not exist).")
  var outputCheckpoint: String

  @Option(name: .customLong("name"), help: "Checkpoint name recorded in the manifest.")
  var checkpointName: String = "interpolated-derived"

  enum ColumnRangeError: Error {
    case incompleteRange
    case invalidRange(start: Int, end: Int)
  }

  mutating func run() throws {
    var columnRange: Range<Int>? = nil
    switch (columnStart, columnEnd) {
    case (nil, nil):
      break
    case let (start?, end?):
      guard start >= 0, end > start else {
        throw ColumnRangeError.invalidRange(start: start, end: end)
      }
      columnRange = start..<end
    default:
      throw ColumnRangeError.incompleteRange
    }
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
      checkpointName: checkpointName,
      keyPrefixes: keyPrefixes,
      columnRange: columnRange
    )
    print("[derive-interpolated-checkpoint] wrote \(outputCheckpoint)")
    print("[derive-interpolated-checkpoint] factor=\(factor) (weight of checkpoint B)")
    if !keyPrefixes.isEmpty {
      print("[derive-interpolated-checkpoint] key-prefixes=\(keyPrefixes.joined(separator: ","))")
    }
    if let columnRange {
      print(
        "[derive-interpolated-checkpoint] columns=\(columnRange.lowerBound)..<\(columnRange.upperBound)"
      )
    }
  }
}
