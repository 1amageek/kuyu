import KuyuTraining

public protocol LearningUpdateRunning: Sendable {
  func execute(
    _ request: LearningUpdateRequest
  ) async throws -> LearningUpdateResult

  func cancel() async
}
