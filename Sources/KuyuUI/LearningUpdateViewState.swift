import KuyuTrainingContracts

public enum LearningUpdateViewState: Sendable, Equatable {
  case idle
  case running
  case completed(
    candidateBundleID: String,
    transitionCount: Int,
    metrics: LearningUpdateMetrics
  )
  case cancelled
  case failed(String)
}
