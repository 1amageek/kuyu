public enum LearningUpdateRequestFactoryError: Error, Sendable, Equatable {
  case emptyValue(field: String)
  case pathIsNotAbsolute(field: String, path: String)
  case missingDirectory(field: String, path: String)
  case candidateAlreadyExists(path: String)
  case pathCollision(first: String, second: String)
}
