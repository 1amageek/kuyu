import Foundation
import KuyuTraining

public struct FileSystemLearningUpdateRequestFactory: Sendable {
  public init() {}

  public func request(
    runID: String,
    datasetPath: String,
    sourceBundleID: String,
    sourceBundlePath: String,
    candidateBundleID: String,
    candidateBundlePath: String,
    plan: LearningUpdatePlan = LearningUpdatePlan()
  ) throws -> LearningUpdateRequest {
    try requireValue(runID, field: "runID")
    try requireValue(sourceBundleID, field: "sourceBundleID")
    try requireValue(candidateBundleID, field: "candidateBundleID")
    let dataset = try existingDirectory(
      datasetPath,
      field: "datasetPath"
    )
    let source = try existingDirectory(
      sourceBundlePath,
      field: "sourceBundlePath"
    )
    let candidate = try absoluteDirectoryURL(
      candidateBundlePath,
      field: "candidateBundlePath"
    )
    guard !FileManager.default.fileExists(atPath: candidate.path) else {
      throw LearningUpdateRequestFactoryError.candidateAlreadyExists(
        path: candidate.path
      )
    }
    let resolvedCandidate = candidate.resolvingSymlinksInPath()
    guard !pathsOverlap(dataset, source) else {
      throw LearningUpdateRequestFactoryError.pathCollision(
        first: "datasetPath",
        second: "sourceBundlePath"
      )
    }
    guard !pathsOverlap(resolvedCandidate, dataset) else {
      throw LearningUpdateRequestFactoryError.pathCollision(
        first: "candidateBundlePath",
        second: "datasetPath"
      )
    }
    guard !pathsOverlap(resolvedCandidate, source) else {
      throw LearningUpdateRequestFactoryError.pathCollision(
        first: "candidateBundlePath",
        second: "sourceBundlePath"
      )
    }
    let sourceReference = try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [source.deletingLastPathComponent()]
    ).pinnedReference(
      ModelBundleReference(
        bundleID: sourceBundleID,
        kind: .source,
        url: source
      )
    )
    return LearningUpdateRequest(
      runID: TrainingRunID(runID),
      datasetURL: dataset,
      sourceBundle: sourceReference,
      candidateBundleID: candidateBundleID,
      candidateBundleURL: candidate,
      plan: plan
    )
  }

  private func requireValue(
    _ value: String,
    field: String
  ) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw LearningUpdateRequestFactoryError.emptyValue(field: field)
    }
  }

  private func existingDirectory(
    _ path: String,
    field: String
  ) throws -> URL {
    let url = try absoluteDirectoryURL(path, field: field)
      .resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: url.path,
        isDirectory: &isDirectory
      ),
      isDirectory.boolValue
    else {
      throw LearningUpdateRequestFactoryError.missingDirectory(
        field: field,
        path: url.path
      )
    }
    return url
  }

  private func absoluteDirectoryURL(
    _ path: String,
    field: String
  ) throws -> URL {
    try requireValue(path, field: field)
    guard NSString(string: path).isAbsolutePath else {
      throw LearningUpdateRequestFactoryError.pathIsNotAbsolute(
        field: field,
        path: path
      )
    }
    return URL(fileURLWithPath: path, isDirectory: true)
      .standardizedFileURL
  }

  private func pathsOverlap(_ first: URL, _ second: URL) -> Bool {
    first == second
      || isDescendant(first, of: second)
      || isDescendant(second, of: first)
  }

  private func isDescendant(_ candidate: URL, of root: URL) -> Bool {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    return candidate.path.hasPrefix(rootPath)
  }
}
