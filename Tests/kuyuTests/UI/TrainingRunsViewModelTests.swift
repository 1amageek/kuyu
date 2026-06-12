import Foundation
import KuyuTraining
import Testing
@testable import KuyuUI

// TrainingRunsViewModel coverage against real run-contract directories.
// Fixtures are produced by the real TrainingRunDriver, so the UI reads
// exactly what a trainer writes — list snapshots, per-run detail, and the
// file-based control channel round trip.

private func makeRunsViewModelTestRoot(label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-runs-\(label)-\(UUID().uuidString)", isDirectory: true)
}

private func removeRunsViewModelTestRoot(_ runRoot: URL) {
    do {
        try FileManager.default.removeItem(at: runRoot)
    } catch {
        Issue.record("Failed to remove temporary run root \(runRoot.path): \(error)")
    }
}

private func beginRunsViewModelTestRun(runRoot: URL) throws -> TrainingRunDriver {
    try TrainingRunDriver.begin(
        task: "ui-runs-test",
        profile: "P1",
        semanticVersion: "ui-runs-test-v1",
        cacheKey: "ui-runs-test-cache-v1",
        mlxGlobalSeed: 0,
        noiseSeedSalt: nil,
        determinismTier: 0,
        runRoot: runRoot,
        repositoryDirectory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    )
}

@MainActor
@Test(.timeLimit(.minutes(1))) func trainingRunsViewModelListsAndSnapshotsCompletedRun() async throws {
    let runRoot = makeRunsViewModelTestRoot(label: "list")
    defer { removeRunsViewModelTestRoot(runRoot) }

    let driver = try beginRunsViewModelTestRun(runRoot: runRoot)
    try driver.recordIteration(TrainingRunIterationRecord(
        iteration: 0,
        recordedAt: Date(),
        evaluation: TrainingRunIterationRecord.EvaluationRecord(
            evaluationHorizon: 0,
            metrics: ["score": 0.5]
        )
    ))
    try driver.finishCompleted(acceptedCheckpointPath: nil)

    let model = TrainingRunsViewModel(environment: ["KUYU_RUN_ROOT": runRoot.path])
    await model.refresh()

    #expect(model.lastError == nil)
    #expect(model.runRootPath == runRoot.path)
    #expect(model.items.count == 1)
    #expect(model.items.first?.liveness == .finished(.completed))
    #expect(model.items.first?.task == "ui-runs-test")
    #expect(model.detail == nil)

    model.selectedRunID = model.items.first?.id
    await model.refresh()

    let detail = try #require(model.detail)
    #expect(detail.runID == driver.runIDString)
    #expect(detail.liveness == .finished(.completed))
    #expect(detail.outcome.status == .completed)
    #expect(detail.journalRecordCount == 1)
    #expect(detail.journalTruncatedTailBytes == 0)
    #expect(detail.lastRecord?.evaluation?.metrics["score"] == 0.5)
    #expect(detail.control == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func trainingRunsViewModelReportsUnreadableRunDirectories() async throws {
    let runRoot = makeRunsViewModelTestRoot(label: "unreadable")
    defer { removeRunsViewModelTestRoot(runRoot) }

    let brokenRun = runRoot.appendingPathComponent("broken-run", isDirectory: true)
    try FileManager.default.createDirectory(at: brokenRun, withIntermediateDirectories: true)

    let model = TrainingRunsViewModel(environment: ["KUYU_RUN_ROOT": runRoot.path])
    await model.refresh()

    #expect(model.lastError == nil)
    #expect(model.items.count == 1)
    let item = try #require(model.items.first)
    #expect(item.id == "broken-run")
    #expect(item.liveness == nil)
    #expect(item.unreadableReason != nil)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func trainingRunsViewModelRejectsControlOnFinishedRun() async throws {
    let runRoot = makeRunsViewModelTestRoot(label: "rejected-control")
    defer { removeRunsViewModelTestRoot(runRoot) }

    let driver = try beginRunsViewModelTestRun(runRoot: runRoot)
    try driver.finishCompleted(acceptedCheckpointPath: nil)

    let model = TrainingRunsViewModel(environment: ["KUYU_RUN_ROOT": runRoot.path])
    await model.refresh()
    model.selectedRunID = driver.runIDString
    await model.refresh()

    await model.submitControl(.pause)

    let lastError = try #require(model.lastError)
    #expect(lastError.contains("already finished"))
    #expect(model.pendingControlSequence == nil)
    let detail = try #require(model.detail)
    #expect(detail.control == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func trainingRunsViewModelControlRoundTripWithLiveDriver() async throws {
    let runRoot = makeRunsViewModelTestRoot(label: "control-round-trip")
    defer { removeRunsViewModelTestRoot(runRoot) }

    // The driver lives in this test process, so liveness reads `live`.
    let driver = try beginRunsViewModelTestRun(runRoot: runRoot)

    let model = TrainingRunsViewModel(environment: ["KUYU_RUN_ROOT": runRoot.path])
    await model.refresh()
    model.selectedRunID = driver.runIDString
    await model.refresh()
    #expect(model.detail?.liveness == .live(processIdentifier: ProcessInfo.processInfo.processIdentifier))

    await model.submitControl(.stop)
    #expect(model.lastError == nil)
    #expect(model.pendingControlSequence == 1)
    let pendingControl = try #require(model.detail?.control)
    #expect(pendingControl.sequence == 1)
    #expect(pendingControl.acknowledgment == nil)

    // The trainer applies the command at the next iteration boundary.
    let directive = try await driver.applyPendingControl(iteration: 0)
    #expect(directive == .stopRun)
    try driver.finishCancelled(acceptedCheckpointPath: nil)

    await model.refresh()
    #expect(model.pendingControlSequence == nil)
    let detail = try #require(model.detail)
    #expect(detail.liveness == .finished(.cancelled))
    let acknowledgment = try #require(detail.control?.acknowledgment)
    #expect(acknowledgment.command == "stop")
    #expect(acknowledgment.rejected == false)
    #expect(acknowledgment.iteration == 0)
}
