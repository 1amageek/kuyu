import KuyuTrainingApplication
import KuyuTrainingContracts
import Observation

@MainActor
@Observable
public final class LearningUpdateViewModel {
  public var runID = "local-update"
  public var datasetPath = ""
  public var sourceBundleID = ""
  public var sourceBundlePath = ""
  public var candidateBundleID = "candidate"
  public var candidateBundlePath = ""
  public private(set) var state: LearningUpdateViewState = .idle

  @ObservationIgnored
  private let runner: any LearningUpdateRunning
  @ObservationIgnored
  private let requestFactory: FileSystemLearningUpdateRequestFactory
  @ObservationIgnored
  private var activeTask: Task<Void, Never>?

  public init(
    runner: any LearningUpdateRunning,
    requestFactory: FileSystemLearningUpdateRequestFactory =
      FileSystemLearningUpdateRequestFactory()
  ) {
    self.runner = runner
    self.requestFactory = requestFactory
  }

  public func start(plan: LearningUpdatePlan = LearningUpdatePlan()) {
    guard activeTask == nil else {
      return
    }
    KuyuUIEventLogger.record(
      action: "start",
      task: "learning-update",
      identifier: runID
    )
    let request: LearningUpdateRequest
    do {
      request = try requestFactory.request(
        runID: runID,
        datasetPath: datasetPath,
        sourceBundleID: sourceBundleID,
        sourceBundlePath: sourceBundlePath,
        candidateBundleID: candidateBundleID,
        candidateBundlePath: candidateBundlePath,
        plan: plan
      )
    } catch {
      KuyuUIEventLogger.record(
        action: "validation-failed",
        task: "learning-update",
        identifier: runID
      )
      state = .failed(String(describing: error))
      return
    }
    state = .running
    let runner = self.runner
    activeTask = Task { [weak self] in
      do {
        let result = try await runner.execute(request)
        guard let self else {
          return
        }
        state = .completed(
          candidateBundleID: result.candidate.bundleID,
          transitionCount: result.transitionCount,
          metrics: result.metrics
        )
        activeTask = nil
      } catch is CancellationError {
        guard let self else {
          return
        }
        state = .cancelled
        activeTask = nil
      } catch {
        guard let self else {
          return
        }
        state = .failed(String(describing: error))
        activeTask = nil
      }
    }
  }

  public func cancel() {
    KuyuUIEventLogger.record(
      action: "cancel",
      task: "learning-update",
      identifier: runID
    )
    activeTask?.cancel()
    let runner = self.runner
    Task {
      await runner.cancel()
    }
  }
}
