import Foundation
import KuyuTrainingApplication
import KuyuTrainingContracts
import Testing

@Suite("Learning update coordinator")
struct LearningUpdateCoordinatorTests {
  @Test(.timeLimit(.minutes(1)))
  func serializesUpdatesAndReturnsTheExecutorResult() async throws {
    let executor = ControlledLearningUpdateExecutor()
    let coordinator = LearningUpdateCoordinator(executor: executor)
    let request = learningRequest()
    let expected = learningResult()
    let first = Task {
      try await coordinator.execute(request)
    }
    await executor.waitUntilStarted()

    do {
      _ = try await coordinator.execute(request)
      Issue.record("A concurrent update unexpectedly started")
    } catch let error as LearningUpdateCoordinatorError {
      #expect(error == .updateAlreadyRunning)
    }

    await executor.finish(with: expected)
    #expect(try await first.value == expected)
    #expect(await coordinator.isExecuting == false)
  }

  @Test(.timeLimit(.minutes(1)))
  func cancellationPropagatesToTheExecutor() async throws {
    let executor = CancellationLearningUpdateExecutor()
    let coordinator = LearningUpdateCoordinator(executor: executor)
    let update = Task {
      try await coordinator.execute(learningRequest())
    }
    while await coordinator.isExecuting == false {
      await Task.yield()
    }
    await coordinator.cancel()

    do {
      _ = try await update.value
      Issue.record("A cancelled update unexpectedly completed")
    } catch is CancellationError {
      #expect(Bool(true))
    }
  }
}

private actor ControlledLearningUpdateExecutor: LearningUpdateExecuting {
  private var started = false
  private var continuation:
    CheckedContinuation<LearningUpdateResult, Error>?

  func execute(
    _ request: LearningUpdateRequest
  ) async throws -> LearningUpdateResult {
    started = true
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilStarted() async {
    while !started {
      await Task.yield()
    }
  }

  func finish(with result: LearningUpdateResult) {
    continuation?.resume(returning: result)
    continuation = nil
  }
}

private struct CancellationLearningUpdateExecutor:
  LearningUpdateExecuting, Sendable
{
  func execute(
    _ request: LearningUpdateRequest
  ) async throws -> LearningUpdateResult {
    try await Task.sleep(for: .seconds(30))
    return learningResult()
  }
}

private func learningRequest() -> LearningUpdateRequest {
  LearningUpdateRequest(
    runID: "run",
    datasetURL: URL(fileURLWithPath: "/tmp/dataset", isDirectory: true),
    sourceBundle: ModelBundleReference(
      bundleID: "source",
      kind: .source,
      url: URL(fileURLWithPath: "/tmp/source", isDirectory: true),
      contentHash: String(repeating: "a", count: 64)
    ),
    candidateBundleID: "candidate",
    candidateBundleURL: URL(
      fileURLWithPath: "/tmp/candidate",
      isDirectory: true
    ),
    plan: LearningUpdatePlan()
  )
}

private func learningResult() -> LearningUpdateResult {
  LearningUpdateResult(
    runID: "run",
    source: LearningUpdateSourceIdentity(
      datasetID: "dataset",
      recordsDigest: String(repeating: "a", count: 64),
      policyID: "policy",
      checkpointDigest: String(repeating: "b", count: 64),
      actorInputContractDigest: String(repeating: "c", count: 64),
      criticInputContractDigest: String(repeating: "d", count: 64)
    ),
    transitionCount: 1,
    metrics: LearningUpdateMetrics(
      updateCount: 1,
      policyLoss: 0,
      rewardValueLoss: 0,
      costValueLoss: 0,
      entropy: 0,
      approximateKL: 0,
      clipFraction: 0,
      rewardAdvantageMean: 0,
      costAdvantageMean: 0,
      gradientNorm: 0,
      lagrangeMultiplier: 0
    ),
    candidate: ModelBundleReference(
      bundleID: "candidate",
      kind: .candidate,
      url: URL(fileURLWithPath: "/tmp/candidate", isDirectory: true),
      contentHash: String(repeating: "e", count: 64)
    )
  )
}
