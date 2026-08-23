import Foundation
import KuyuTrainingApplication
import Testing

@Suite("Learning update request factory")
struct FileSystemLearningUpdateRequestFactoryTests {
  @Test(.timeLimit(.minutes(1)))
  func pinsTheSourceAndPreservesApplicationInputs() throws {
    try withTemporaryDirectory { root in
      let dataset = root.appendingPathComponent("dataset", isDirectory: true)
      let source = root.appendingPathComponent("source", isDirectory: true)
      let candidate = root.appendingPathComponent(
        "candidate",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: dataset,
        withIntermediateDirectories: false
      )
      try FileManager.default.createDirectory(
        at: source,
        withIntermediateDirectories: false
      )
      try Data("dataset".utf8).write(
        to: dataset.appendingPathComponent("manifest.json")
      )
      try Data("model".utf8).write(
        to: source.appendingPathComponent("model.json")
      )

      let request = try FileSystemLearningUpdateRequestFactory().request(
        runID: "run",
        datasetPath: dataset.path,
        sourceBundleID: "source-id",
        sourceBundlePath: source.path,
        candidateBundleID: "candidate-id",
        candidateBundlePath: candidate.path
      )

      #expect(request.runID.rawValue == "run")
      #expect(request.datasetURL == dataset)
      #expect(request.sourceBundle.bundleID == "source-id")
      #expect(request.sourceBundle.contentHash?.count == 64)
      #expect(request.candidateBundleID == "candidate-id")
      #expect(request.candidateBundleURL == candidate)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsAnExistingCandidateBeforeExecution() throws {
    try withTemporaryDirectory { root in
      let dataset = root.appendingPathComponent("dataset", isDirectory: true)
      let source = root.appendingPathComponent("source", isDirectory: true)
      let candidate = root.appendingPathComponent(
        "candidate",
        isDirectory: true
      )
      for directory in [dataset, source, candidate] {
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: false
        )
      }

      #expect(
        throws: LearningUpdateRequestFactoryError.candidateAlreadyExists(
          path: candidate.path
        )
      ) {
        _ = try FileSystemLearningUpdateRequestFactory().request(
          runID: "run",
          datasetPath: dataset.path,
          sourceBundleID: "source-id",
          sourceBundlePath: source.path,
          candidateBundleID: "candidate-id",
          candidateBundlePath: candidate.path
        )
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsACandidateNestedInsideTheImmutableSource() throws {
    try withTemporaryDirectory { root in
      let dataset = root.appendingPathComponent("dataset", isDirectory: true)
      let source = root.appendingPathComponent("source", isDirectory: true)
      let candidate = source.appendingPathComponent(
        "candidate",
        isDirectory: true
      )
      for directory in [dataset, source] {
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: false
        )
      }

      #expect(
        throws: LearningUpdateRequestFactoryError.pathCollision(
          first: "candidateBundlePath",
          second: "sourceBundlePath"
        )
      ) {
        _ = try FileSystemLearningUpdateRequestFactory().request(
          runID: "run",
          datasetPath: dataset.path,
          sourceBundleID: "source-id",
          sourceBundlePath: source.path,
          candidateBundleID: "candidate-id",
          candidateBundlePath: candidate.path
        )
      }
    }
  }
}

private func withTemporaryDirectory<Result>(
  _ operation: (URL) throws -> Result
) throws -> Result {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "kuyu-application-tests-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(
    at: root,
    withIntermediateDirectories: false
  )
  do {
    let result = try operation(root)
    try FileManager.default.removeItem(at: root)
    return result
  } catch {
    let operationError = error
    do {
      try FileManager.default.removeItem(at: root)
    } catch {
      throw TemporaryDirectoryCleanupError(
        operation: String(describing: operationError),
        cleanup: String(describing: error)
      )
    }
    throw operationError
  }
}

private struct TemporaryDirectoryCleanupError: Error {
  let operation: String
  let cleanup: String
}
