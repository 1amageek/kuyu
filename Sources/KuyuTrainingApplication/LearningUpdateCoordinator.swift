import KuyuTraining

public actor LearningUpdateCoordinator: LearningUpdateRunning {
  private let executor: AnyLearningUpdateExecutor
  private var activeUpdate: Task<LearningUpdateResult, Error>?

  public init(executor: any LearningUpdateExecuting) {
    self.executor = AnyLearningUpdateExecutor { request in
      try await executor.execute(request)
    }
  }

  public var isExecuting: Bool {
    activeUpdate != nil
  }

  public func execute(
    _ request: LearningUpdateRequest
  ) async throws -> LearningUpdateResult {
    guard activeUpdate == nil else {
      throw LearningUpdateCoordinatorError.updateAlreadyRunning
    }
    let update = Task {
      try await executor.execute(request)
    }
    activeUpdate = update
    defer {
      activeUpdate = nil
    }
    return try await withTaskCancellationHandler {
      try await update.value
    } onCancel: {
      update.cancel()
    }
  }

  public func cancel() async {
    activeUpdate?.cancel()
  }
}
