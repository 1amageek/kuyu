import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuTraining
import KuyuWorkerRuntime

struct RunLearningCampaignWorker: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run-learning-campaign-worker",
    abstract: "Execute one immutable, digest-bound training run launch."
  )

  @Option(name: .customLong("launch-root"), help: "Absolute training worker launch store root.")
  var launchRootPath: String

  @Option(name: .customLong("launch-id"), help: "Immutable training worker launch identifier.")
  var launchIDValue: String

  @Option(
    name: .customLong("launch-digest"), help: "Expected SHA-256 digest of the launch artifact.")
  var launchDigest: String

  @Option(
    name: .customLong("allowed-artifact-root"),
    help: "Trusted parent for the destination artifact root. Repeat as needed."
  )
  var allowedArtifactRootPaths: [String] = []

  @Option(
    name: .customLong("allowed-source-root"),
    help: "Trusted parent for source checkpoints. Repeat as needed."
  )
  var allowedSourceRootPaths: [String] = []

  @Option(
    name: .customLong("allowed-project-root"),
    help: "Trusted parent for project roots. Repeat as needed."
  )
  var allowedProjectRootPaths: [String] = []

  mutating func run() async throws {
    guard let launchID = UUID(uuidString: launchIDValue) else {
      throw ValidationError("--launch-id must be a UUID.")
    }
    let invocation = try ManasMLXTrainingWorkerInvocation(
      launchRoot: URL(fileURLWithPath: launchRootPath, isDirectory: true),
      launchID: launchID,
      launchDigest: launchDigest,
      allowedArtifactRoots: allowedArtifactRootPaths.map {
        URL(fileURLWithPath: $0, isDirectory: true)
      },
      allowedSourceRoots: allowedSourceRootPaths.map {
        URL(fileURLWithPath: $0, isDirectory: true)
      },
      allowedProjectRoots: allowedProjectRootPaths.map {
        URL(fileURLWithPath: $0, isDirectory: true)
      }
    )
    let reporter = LearningCampaignConsoleReporter()
    let executionTask = Task {
      try await ManasMLXTrainingWorkerService().execute(invocation) { event in
        _ = reporter.report(event)
      }
    }
    let signalRecorder = LearningCampaignProcessSignal.Recorder()
    let signalMonitor = RunLearningCampaign.installStopSignalHandlers { signal in
      await signalRecorder.record(signal)
      executionTask.cancel()
    }
    defer {
      signalMonitor.cancel()
      RunLearningCampaign.restoreStopSignalHandlers()
    }
    let outcome = try await executionTask.value
    print(
      "[learning-campaign-worker] finished runID=\(outcome.runID) terminalState=\(outcome.terminalState.rawValue) generations=\(outcome.generationCount) candidates=\(outcome.candidateCount) artifacts=\(outcome.artifactRoot.path)"
    )
    switch outcome.processDisposition {
    case .success:
      return
    case .rejection:
      FileHandle.standardError.write(
        Data(
          "[learning-campaign-worker] training worker rejected the candidate: \(outcome.failureReasons.joined(separator: ", "))\n".utf8
        )
      )
      throw ExitCode(outcome.processDisposition.exitStatus)
    case .cancellation:
      let signal = await signalRecorder.receivedSignal()
      throw signal.map { ExitCode($0.exitCode) }
        ?? ExitCode(outcome.processDisposition.exitStatus)
    case .failure, .invalidOutcome:
      FileHandle.standardError.write(
        Data(
          "[learning-campaign-worker] training worker ended with \(outcome.terminalState.rawValue): \(outcome.failureReasons.joined(separator: ", "))\n".utf8
        )
      )
      throw ExitCode(outcome.processDisposition.exitStatus)
    }
  }
}
