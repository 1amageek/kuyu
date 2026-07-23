import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
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
        mlxRandomSeedBase: 0,
        mlxRandomnessContractID: "mlx-task-local-random-state-v1",
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
@Test(.timeLimit(.minutes(1))) func trainingRunsViewModelLoadsValidatedEvaluationMatrix() async throws {
    let runRoot = makeRunsViewModelTestRoot(label: "evaluation-matrix")
    defer { removeRunsViewModelTestRoot(runRoot) }

    let driver = try beginRunsViewModelTestRun(runRoot: runRoot)
    let runDirectory = URL(fileURLWithPath: driver.runDirectoryPath, isDirectory: true)
    let artifactDirectory = runDirectory
        .appendingPathComponent("evaluations", isDirectory: true)
        .appendingPathComponent("iteration-1", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

    let scenarioKey = CheckpointEvaluationScenarioKey(scenarioID: "scenario-a", seed: 7)
    let artifact = CheckpointEvaluationArtifact(
        evaluationID: "evaluation-a",
        startedAt: Date(timeIntervalSince1970: 1),
        task: "attitude",
        profileID: "attitude-v1",
        checkpointPath: "/tmp/checkpoint-a",
        teacherScore: 1,
        policyScore: 0.25,
        teacherPassed: true,
        policyPassed: false,
        failureReasons: ["sustained-fall"],
        expectedQualityKeys: [scenarioKey],
        qualitySummary: [
            ReferenceQuadrotorTaskQualitySummary(
                task: "attitude",
                scenarioID: "scenario-a",
                seed: 7,
                passed: false,
                failureReasons: ["sustained-fall"],
                evaluatorID: "ReferenceQuadrotorTaskQualityEvaluator",
                targetZ: nil,
                tolerance: nil,
                warmupTime: nil,
                requiredHoldTime: nil,
                achievedHoldTime: nil,
                maxAltitudeErrorAfterWarmup: nil,
                maxVerticalVelocityAfterWarmup: nil
            ),
        ],
        scenarioHorizons: [
            CheckpointEvaluationScenarioHorizon(
                scenarioID: "scenario-a",
                seed: 7,
                durationSeconds: 20,
                timeStepSeconds: 0.001,
                stepCount: 20_000
            ),
        ],
        motorMAE: nil,
        driveMAE: nil,
        finalAltitudeDelta: nil,
        policyAverageMotorFinalOutputByIndex: nil,
        teacherAverageMotorFinalOutputByIndex: nil,
        diagnostics: nil
    )
    try TrainingRunContractCodec.makeDocumentEncoder().encode(artifact).write(
        to: artifactDirectory.appendingPathComponent(CheckpointEvaluationArtifact.fileName),
        options: [.atomic]
    )
    try driver.recordIteration(TrainingRunIterationRecord(
        iteration: 0,
        recordedAt: Date(),
        evaluation: TrainingRunIterationRecord.EvaluationRecord(
            evaluationHorizon: 20_000,
            metrics: ["policyPassed": 0, "policyScore": 0.25],
            artifacts: [
                TrainingRunIterationRecord.EvaluationRecord.ArtifactReference(
                    kind: CheckpointEvaluationArtifact.artifactKind,
                    path: "evaluations/iteration-1/\(CheckpointEvaluationArtifact.fileName)"
                ),
            ]
        )
    ))
    try driver.finishCancelled(acceptedCheckpointPath: nil)

    let model = TrainingRunsViewModel(environment: ["KUYU_RUN_ROOT": runRoot.path])
    await model.refresh()
    model.selectedRunID = driver.runIDString
    await model.refresh()

    #expect(model.lastError == nil)
    let detail = try #require(model.detail)
    #expect(detail.latestEvaluation == artifact)
    #expect(detail.evaluationProfile?.profileID == "attitude-v1")
    let matrix = TrainingRunTestMatrixSnapshot(artifact: artifact)
    #expect(matrix.scenarioIDs == ["scenario-a"])
    #expect(matrix.seeds == [7])
    #expect(matrix.failedCount == 1)
    #expect(matrix.testCases[0].stepCount == 20_000)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func trainingRunsViewModelRejectsMissingEvaluationArtifactReferences() async throws {
    let runRoot = makeRunsViewModelTestRoot(label: "missing-eval-artifact")
    defer { removeRunsViewModelTestRoot(runRoot) }

    let driver = try beginRunsViewModelTestRun(runRoot: runRoot)
    try driver.recordIteration(TrainingRunIterationRecord(
        iteration: 0,
        recordedAt: Date(),
        evaluation: TrainingRunIterationRecord.EvaluationRecord(
            evaluationHorizon: 20_000,
            metrics: ["policyPassed": 0],
            artifacts: [
                TrainingRunIterationRecord.EvaluationRecord.ArtifactReference(
                    kind: "checkpoint-evaluation",
                    path: "evaluations/iteration-0/missing.json"
                ),
            ]
        )
    ))
    try driver.finishCancelled(acceptedCheckpointPath: nil)

    let model = TrainingRunsViewModel(environment: ["KUYU_RUN_ROOT": runRoot.path])
    await model.refresh()
    #expect(model.lastError == nil)
    #expect(model.items.count == 1)

    model.selectedRunID = driver.runIDString
    await model.refresh()

    let lastError = try #require(model.lastError)
    #expect(lastError.contains("missing artifact file"))
    #expect(lastError.contains("evaluations/iteration-0/missing.json"))
}

@MainActor
@Test(.timeLimit(.minutes(1))) func trainingRunsViewModelRejectsDuplicateEvaluationArtifactKinds() async throws {
    let runRoot = makeRunsViewModelTestRoot(label: "duplicate-eval-artifact")
    defer { removeRunsViewModelTestRoot(runRoot) }

    let driver = try beginRunsViewModelTestRun(runRoot: runRoot)
    let runDirectory = URL(fileURLWithPath: driver.runDirectoryPath, isDirectory: true)
    let artifactDirectory = runDirectory
        .appendingPathComponent("evaluations", isDirectory: true)
        .appendingPathComponent("iteration-0", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
    try Data("{}".utf8).write(
        to: artifactDirectory.appendingPathComponent("checkpoint-evaluation.json"),
        options: [.atomic]
    )
    try Data("{}".utf8).write(
        to: artifactDirectory.appendingPathComponent("checkpoint-evaluation-copy.json"),
        options: [.atomic]
    )
    try driver.recordIteration(TrainingRunIterationRecord(
        iteration: 0,
        recordedAt: Date(),
        evaluation: TrainingRunIterationRecord.EvaluationRecord(
            evaluationHorizon: 20_000,
            metrics: ["policyPassed": 0],
            artifacts: [
                TrainingRunIterationRecord.EvaluationRecord.ArtifactReference(
                    kind: "checkpoint-evaluation",
                    path: "evaluations/iteration-0/checkpoint-evaluation.json"
                ),
                TrainingRunIterationRecord.EvaluationRecord.ArtifactReference(
                    kind: "checkpoint-evaluation",
                    path: "evaluations/iteration-0/checkpoint-evaluation-copy.json"
                ),
            ]
        )
    ))
    try driver.finishCancelled(acceptedCheckpointPath: nil)

    let model = TrainingRunsViewModel(environment: ["KUYU_RUN_ROOT": runRoot.path])
    await model.refresh()
    #expect(model.lastError == nil)
    #expect(model.items.count == 1)

    model.selectedRunID = driver.runIDString
    await model.refresh()

    let lastError = try #require(model.lastError)
    #expect(lastError.contains("duplicate artifact kind"))
    #expect(lastError.contains("checkpoint-evaluation"))
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

private func makeGeneratedArtifactScenarioRuns(runID: String) throws -> [TrainingScenarioRunArtifact] {
    [
        TrainingScenarioRunArtifact(
            runID: runID,
            iteration: 1,
            summary: TrainingScenarioRunSummary(
                suitePassed: true,
                evaluations: [
                    try TrainingScenarioEvaluationRecord(
                        scenarioID: "ui-generated-artifact-scenario",
                        seed: 1,
                        passed: true,
                        maxOmega: 0.1,
                        maxTiltDegrees: 1,
                        sustainedViolationSeconds: 0,
                        recoveryTimeSeconds: 0.1,
                        overshootDegrees: 1,
                        hfStabilityScore: 0.9,
                        failures: []
                    )
                ],
                aggregate: TrainingScenarioEvaluationAggregate(
                    averageRecoveryTime: 0.1,
                    worstOvershootDegrees: 1,
                    averageHfStabilityScore: 0.9
                ),
                replay: .performed([
                    ReplayCheckResult(
                        scenarioId: try ScenarioID("ui-generated-artifact-scenario"),
                        seed: ScenarioSeed(1),
                        tier: .tier0,
                        passed: true,
                        issues: [],
                        residuals: .zero
                    )
                ])
            ),
            logCount: 1,
            terminalFactCount: 1
        )
    ]
}
