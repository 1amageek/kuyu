import Foundation
import KuyuMLX
import KuyuMLXCampaignContracts
import KuyuTraining
@testable import KuyuUI
import Testing

@MainActor
@Test(.timeLimit(.minutes(1))) func simulationViewModelLiveMetricsKeepGenerationBestSeries() {
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))

    model.appendLearningCampaignLiveMetricSamples(makeFitness(
        generationIndex: 0,
        candidateID: "g0-c0",
        scalarFitness: -10,
        rewardAverage: -20,
        taskPassRate: 0.25
    ))
    model.appendLearningCampaignLiveMetricSamples(makeFitness(
        generationIndex: 0,
        candidateID: "g0-c1",
        scalarFitness: -12,
        rewardAverage: -30,
        taskPassRate: 0.1
    ))
    model.appendLearningCampaignLiveMetricSamples(makeFitness(
        generationIndex: 0,
        candidateID: "g0-c2",
        scalarFitness: -8,
        rewardAverage: -18,
        taskPassRate: 0.5
    ))
    model.appendLearningCampaignLiveMetricSamples(makeFitness(
        generationIndex: 1,
        candidateID: "g1-c0",
        scalarFitness: -7,
        rewardAverage: -16,
        taskPassRate: 0.75
    ))

    #expect(model.learningCampaignLiveCandidateEvaluationCount == 4)
    #expect(model.learningCampaignLiveFitnessSamples.map { $0.time } == [0, 1])
    #expect(model.learningCampaignLiveFitnessSamples.map { $0.value } == [-8, -7])
    #expect(model.learningCampaignLiveRewardSamples.map { $0.value } == [-18, -16])
    #expect(model.learningCampaignLiveTaskPassSamples.map { $0.value } == [0.5, 0.75])
}

@MainActor
@Test(.timeLimit(.minutes(1))) func simulationViewModelExposesLiveVectorizedProgressForDashboardViews() {
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.appendLearningCampaignLiveProgressRecord(
        LearningCampaignProgressEvent(
            event: "candidate-evaluated",
            timestamp: Date(timeIntervalSince1970: 1_778_889_600),
            status: nil,
            exitCode: nil,
            phase: "candidate",
            seed: "seed-1",
            generationIndex: 3,
            candidateID: "g3-c42",
            fitness: -12.5,
            rewardAverage: -4.2,
            taskPassRate: 0.25,
            safetyViolationRate: 0,
            holdTimeRatio: 0.1,
            altitudeErrorRatio: 0.2,
            workerThroughput: 18.5,
            gpuAcceleration: true,
            tensorWorldBatch: true,
            tensorSummary: true,
            vectorizedPopulationSize: 100,
            vectorizedWorldCount: 100,
            vectorizedHistoryLength: 32,
            vectorizedObservationDimension: 64,
            vectorizedActionDimension: 4,
            failureReasons: [],
            message: "Candidate evaluated"
        )
    )

    let records = model.learningCampaignProgressEventsForDisplay

    #expect(records.count == 1)
    #expect(records.first?.candidateID == "g3-c42")
    #expect(records.first?.gpuAcceleration == true)
    #expect(records.first?.tensorWorldBatch == true)
    #expect(records.first?.vectorizedPopulationSize == 100)
    #expect(records.first?.vectorizedWorldCount == 100)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func trainingMonitorSnapshotReportsHealthyLiveCampaign() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.isLearningCampaignRunning = true
    model.learningCampaignMonitorEnabled = true
    model.learningCampaignArtifactDirectory = "/tmp/kuyu-monitor-live"
    model.learningCampaignLastRunnerEventAt = now.addingTimeInterval(-5)
    model.learningCampaignLastArtifactLoadStartedAt = now.addingTimeInterval(-3)
    model.learningCampaignLastArtifactLoadFinishedAt = now.addingTimeInterval(-2)
    model.learningCampaignLastArtifactLoadChangedAt = now.addingTimeInterval(-2)
    model.appendLearningCampaignLiveProgressRecord(
        LearningCampaignProgressEvent(
            event: "candidate-evaluated",
            timestamp: now.addingTimeInterval(-4),
            status: nil,
            exitCode: nil,
            phase: "candidate",
            seed: "seed-1",
            generationIndex: 2,
            candidateID: "g2-c0",
            fitness: -4,
            workerThroughput: 12,
            gpuAcceleration: true,
            tensorWorldBatch: true,
            tensorSummary: true
        )
    )

    let snapshot = TrainingMonitorSnapshot(model: model, now: now)

    #expect(snapshot.health == .healthy)
    #expect(snapshot.eventStreamStatus == "live")
    #expect(snapshot.artifactMonitorStatus == "watching")
    #expect(snapshot.artifactLoadStatus == "loaded")
    #expect(snapshot.throughputText == "12.00 candidates/s")
    #expect(snapshot.alerts.isEmpty)
}

@MainActor
@Suite("Training monitor snapshot ETA")
struct TrainingMonitorSnapshotETATests {
    @Test(.timeLimit(.minutes(1))) func idleCampaignIsNotComplete() {
        let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))

        let snapshot = TrainingMonitorSnapshot(model: model)

        #expect(snapshot.health == .idle)
        #expect(snapshot.progressFraction == 0)
        #expect(snapshot.estimatedRemainingText == "not started")
    }

    @Test(.timeLimit(.minutes(1))) func activeCampaignCollectsEvidenceBeforeAnEstimateExists() {
        let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
        model.isLearningCampaignRunning = true

        let snapshot = TrainingMonitorSnapshot(model: model)

        #expect(snapshot.health == .attention)
        #expect(snapshot.estimatedRemainingText == "collecting evidence")
    }

    @Test(.timeLimit(.minutes(1))) func cancelledCampaignIsNeutralInsteadOfFailed() {
        let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
        model.learningCampaignCurrentPhase = "cancelled"

        let snapshot = TrainingMonitorSnapshot(model: model)

        #expect(snapshot.statusLabel == "cancelled")
        #expect(snapshot.health == .cancelled)
        #expect(snapshot.estimatedRemainingText == "stopped")
    }
}

@MainActor
@Test(.timeLimit(.minutes(1))) func changingArtifactRootClearsPreviousRunPresentation() {
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.learningCampaignArtifactDirectory = "/tmp/kuyu-previous-run"
    model.learningCampaignCurrentPhase = "failed"
    model.learningCampaignProgressFraction = 0.4
    model.learningCampaignLatestEvent = "Previous run failed"

    model.learningCampaignArtifactDirectory = "/tmp/kuyu-next-run"

    #expect(model.learningCampaignState == nil)
    #expect(model.learningCampaignCurrentPhase == "idle")
    #expect(model.learningCampaignProgressFraction == 0)
    #expect(model.learningCampaignLatestEvent == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func trainingMonitorSnapshotRaisesStaleAlerts() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.isLearningCampaignRunning = true
    model.learningCampaignMonitorEnabled = true
    model.learningCampaignArtifactDirectory = "/tmp/kuyu-monitor-stale"
    model.learningCampaignLastRunnerEventAt = now.addingTimeInterval(-900)
    model.learningCampaignLastArtifactLoadStartedAt = now.addingTimeInterval(-900)
    model.learningCampaignLastArtifactLoadFinishedAt = now.addingTimeInterval(-900)
    model.learningCampaignLastArtifactLoadChangedAt = now.addingTimeInterval(-900)
    model.appendLearningCampaignLiveProgressRecord(
        LearningCampaignProgressEvent(
            event: "candidate-evaluated",
            timestamp: now.addingTimeInterval(-900),
            status: nil,
            exitCode: nil,
            phase: "candidate",
            seed: "seed-1",
            generationIndex: 1,
            candidateID: "g1-c0"
        )
    )

    let snapshot = TrainingMonitorSnapshot(model: model, now: now)

    #expect(snapshot.health == .stale)
    #expect(snapshot.alerts.contains { $0.id == "event-stale" })
    #expect(snapshot.alerts.contains { $0.id == "artifact-stale" })
    #expect(snapshot.alerts.contains { $0.id == "candidate-stale" })
}

@MainActor
@Test(.timeLimit(.minutes(1))) func freshControlStepProgressSuppressesCandidateStallWarning() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.isLearningCampaignRunning = true
    model.learningCampaignMonitorEnabled = true
    model.learningCampaignArtifactDirectory = "/tmp/kuyu-monitor-active-work"
    model.learningCampaignLastRunnerEventAt = now.addingTimeInterval(-2)
    model.learningCampaignLastArtifactLoadStartedAt = now.addingTimeInterval(-2)
    model.learningCampaignLastArtifactLoadFinishedAt = now.addingTimeInterval(-1)
    model.learningCampaignLastArtifactLoadChangedAt = now.addingTimeInterval(-1)
    let scope = try TrainingWorkScope(runID: "run", generationIndex: 0)
    let unit = try TrainingWorkUnit(
        kind: .controlStep,
        identifier: "6/A/1/control-step",
        suiteIndex: 6,
        scenarioID: "A",
        scenarioSeed: 1
    )
    let started = try TrainingWorkProgress(
        scope: scope,
        phase: .rollout,
        state: .started,
        unit: unit,
        completedUnitCount: 0,
        totalUnitCount: 1_000,
        timestamp: now.addingTimeInterval(-12)
    )
    let advanced = try TrainingWorkProgress(
        scope: scope,
        phase: .rollout,
        state: .advanced,
        unit: unit,
        completedUnitCount: 500,
        totalUnitCount: 1_000,
        timestamp: now.addingTimeInterval(-2)
    )
    let events = [
        LearningCampaignProgressEvent(
            event: "candidate-evaluated",
            timestamp: now.addingTimeInterval(-900),
            phase: "candidate",
            seed: "seed",
            generationIndex: 0,
            candidateID: "g0-c0"
        ),
        LearningCampaignProgressEvent(
            event: .workProgress(seed: "seed", progress: started),
            timestamp: started.timestamp
        ),
        LearningCampaignProgressEvent(
            event: .workProgress(seed: "seed", progress: advanced),
            timestamp: advanced.timestamp
        ),
    ]
    model.learningCampaignState = LearningCampaignRunStoreState(
        artifactDirectory: URL(fileURLWithPath: "/tmp/kuyu-monitor-active-work"),
        plan: nil,
        status: nil,
        summary: nil,
        validation: nil,
        retention: nil,
        accelerator: nil,
        progressEvents: events,
        generations: [],
        candidates: [],
        vectorizedBatches: [],
        acceptedCheckpoints: []
    )

    let snapshot = TrainingMonitorSnapshot(model: model, now: now)

    #expect(!snapshot.alerts.contains { $0.id == "candidate-stale" })
    #expect(!snapshot.alerts.contains { $0.id == "work-stale" })
    #expect(snapshot.throughputText == "50.0 steps/s")
    #expect(snapshot.scenarioEstimatedRemainingText == "10s")
}

@MainActor
@Test(.timeLimit(.minutes(1))) func trainingMonitorSnapshotDetectsStaleArtifactsDespiteFreshLoaderPoll() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.isLearningCampaignRunning = true
    model.learningCampaignMonitorEnabled = true
    model.learningCampaignArtifactDirectory = "/tmp/kuyu-monitor-stale-artifact"
    model.learningCampaignLastRunnerEventAt = now.addingTimeInterval(-5)
    model.learningCampaignLastArtifactLoadStartedAt = now.addingTimeInterval(-3)
    model.learningCampaignLastArtifactLoadFinishedAt = now.addingTimeInterval(-2)
    model.learningCampaignLastArtifactLoadChangedAt = now.addingTimeInterval(-360)
    model.appendLearningCampaignLiveProgressRecord(
        LearningCampaignProgressEvent(
            event: "candidate-evaluated",
            timestamp: now.addingTimeInterval(-4),
            status: nil,
            exitCode: nil,
            phase: "candidate",
            seed: "seed-1",
            generationIndex: 2,
            candidateID: "g2-c0",
            workerThroughput: 12,
            gpuAcceleration: true
        )
    )

    let snapshot = TrainingMonitorSnapshot(model: model, now: now)

    #expect(snapshot.health == .stale)
    #expect(snapshot.artifactLoadStatus == "loaded")
    #expect(snapshot.alerts.contains { $0.id == "artifact-stale" })
}

@MainActor
@Test(.timeLimit(.minutes(1))) func trainingMonitorSnapshotDetectsStalledArtifactLoader() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.isLearningCampaignRunning = true
    model.learningCampaignMonitorEnabled = true
    model.learningCampaignArtifactDirectory = "/tmp/kuyu-monitor-loader-stalled"
    model.learningCampaignLastRunnerEventAt = now.addingTimeInterval(-5)
    model.learningCampaignLastArtifactLoadStartedAt = now.addingTimeInterval(-360)
    model.appendLearningCampaignLiveProgressRecord(
        LearningCampaignProgressEvent(
            event: "candidate-evaluated",
            timestamp: now.addingTimeInterval(-4),
            status: nil,
            exitCode: nil,
            phase: "candidate",
            seed: "seed-1",
            generationIndex: 2,
            candidateID: "g2-c0",
            workerThroughput: 12,
            gpuAcceleration: true
        )
    )

    let snapshot = TrainingMonitorSnapshot(model: model, now: now)

    #expect(snapshot.health == .stale)
    #expect(snapshot.artifactLoadStatus == "stalled")
    #expect(snapshot.alerts.contains { $0.id == "artifact-loader-stalled" })
}

@MainActor
@Test(.timeLimit(.minutes(1))) func learningCampaignArtifactManualOperationsEmitUIActions() async throws {
    let store = UILogStore(buffer: UILogBuffer())
    let model = SimulationViewModel(logStore: store)
    model.reloadLearningCampaignArtifactsFromUI()
    model.recordLearningCampaignArtifactReveal(path: "/tmp/kuyu-monitor")

    let entries = try await waitForSimulationViewModelUIEntries(store: store) { entries in
        entries.contains { entry in
            entry.metadata["action"] == "reloadLearningCampaignArtifacts" &&
                entry.metadata["reason"] == "emptyArtifactDirectory"
        } && entries.contains { entry in
            entry.metadata["action"] == "revealLearningCampaignArtifactRoot" &&
                entry.metadata["path"] == "/tmp/kuyu-monitor"
        }
    }

    #expect(model.learningCampaignError == "Artifact directory is empty.")
    #expect(entries.contains { entry in
        entry.label == "kuyu.ui" &&
            entry.metadata["action"] == "reloadLearningCampaignArtifacts" &&
            entry.metadata["reason"] == "emptyArtifactDirectory"
    })
    #expect(entries.contains { entry in
        entry.label == "kuyu.ui" &&
            entry.metadata["action"] == "revealLearningCampaignArtifactRoot" &&
            entry.metadata["path"] == "/tmp/kuyu-monitor"
    })
    await store.shutdownAwaitingCompletion()
}

@MainActor
private func waitForSimulationViewModelUIEntries(
    store: UILogStore,
    matching predicate: ([UILogEntry]) -> Bool
) async throws -> [UILogEntry] {
    for _ in 0..<40 {
        let entries = store.entries.filter { $0.label == "kuyu.ui" }
        if predicate(entries) {
            return entries
        }
        try await Task.sleep(for: .milliseconds(25))
    }
    return store.entries.filter { $0.label == "kuyu.ui" }
}

@Test(.timeLimit(.minutes(1))) func gpuActivitySnapshotSummarizesLiveAndBatchExecution() {
    let records = [
        LearningCampaignProgressEvent(
            event: "candidate-evaluated",
            timestamp: Date(timeIntervalSince1970: 1_778_889_600),
            status: nil,
            exitCode: nil,
            phase: "candidate",
            seed: "seed-1",
            generationIndex: 4,
            candidateID: "g4-c0",
            workerThroughput: 12,
            gpuAcceleration: true,
            tensorWorldBatch: true,
            tensorSummary: true
        ),
        LearningCampaignProgressEvent(
            event: "candidate-evaluated",
            timestamp: Date(timeIntervalSince1970: 1_778_889_601),
            status: nil,
            exitCode: nil,
            phase: "candidate",
            seed: "seed-1",
            generationIndex: 4,
            candidateID: "g4-c1",
            workerThroughput: 8,
            gpuAcceleration: false,
            tensorWorldBatch: false,
            tensorSummary: false
        )
    ]
    let batches = [
        LearningCampaignVectorizedBatchState(
            kind: .evaluation,
            seed: "seed-1",
            generationIndex: 4,
            candidateCount: 96,
            completedCandidateCount: 48,
            elapsedSeconds: 6,
            acceleratorDevice: "Apple M4 Max",
            policyExecutionMode: "mlx-temporal-ctbr-policy-v1",
            observationExecutionMode: "mlx-tensor-ctbr-observation-history-v1",
            worldExecutionMode: "mlx-tensor-shared-world-v1",
            actionEncoding: "ctbr",
            worldActiveActionDimension: 4,
            artifactPath: "/tmp/vectorized-evaluations/g4.json",
            bestFitness: -1
        )
    ]

    let snapshot = LearningCampaignGPUActivitySnapshot(
        batches: batches,
        progressEvents: records,
        acceleratorLabel: "Apple M4 Max",
        currentAllocatedBytes: 256,
        recommendedMaxWorkingSetBytes: 1_024
    )

    #expect(snapshot.statusLabel == "ready")
    #expect(snapshot.latestExecutionLabel == "CPU")
    #expect(snapshot.latestThroughput == 8)
    #expect(snapshot.peakThroughput == 12)
    #expect(snapshot.gpuBackedEventCount == 1)
    #expect(snapshot.knownEventCount == 2)
    #expect(snapshot.gpuBackedEventFraction == 0.5)
    #expect(snapshot.gpuBackedBatchCount == 1)
    #expect(snapshot.totalBatchCount == 1)
    #expect(snapshot.gpuBackedBatchFraction == 1)
    #expect(snapshot.latestBatchFillFraction == 0.5)
    #expect(snapshot.metalMemoryFraction == 0.25)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func simulationViewModelBuildsChartSamplesFromProgressEvents() {
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))

    model.appendLearningCampaignLiveProgressEvent(makeProgressEvent(
        generationIndex: 2,
        candidateID: "g2-c0",
        fitness: -12,
        rewardAverage: -30,
        taskPassRate: 0.1
    ))
    model.appendLearningCampaignLiveProgressEvent(makeProgressEvent(
        generationIndex: 2,
        candidateID: "g2-c1",
        fitness: -8,
        rewardAverage: -18,
        taskPassRate: 0.5
    ))
    model.appendLearningCampaignLiveProgressEvent(makeProgressEvent(
        generationIndex: 3,
        candidateID: "g3-c0",
        fitness: -6,
        rewardAverage: -14,
        taskPassRate: 0.75
    ))

    #expect(model.learningCampaignLiveCandidateEvaluationCount == 3)
    #expect(model.learningCampaignLiveFitnessSamples.map(\.time) == [2, 3])
    #expect(model.learningCampaignLiveFitnessSamples.map(\.value) == [-8, -6])
    #expect(model.learningCampaignLiveRewardSamples.map(\.value) == [-18, -14])
    #expect(model.learningCampaignLiveTaskPassSamples.map(\.value) == [0.5, 0.75])
    #expect(model.learningCampaignLiveProgressEvents.last?.gpuAcceleration == true)
    #expect(model.learningCampaignLiveProgressEvents.last?.tensorWorldBatch == true)
    #expect(model.learningCampaignLiveProgressEvents.last?.vectorizedPopulationSize == 100)
}

@MainActor
@Suite("Learning campaign live metrics invariants")
struct LearningCampaignLiveMetricsInvariantTests {
    @Test(.timeLimit(.minutes(1)))
    func persistedAndLiveEventsAreDeduplicated() {
        let metrics = LearningCampaignLiveMetrics()
        let persistedEvent = LearningCampaignProgressEvent(
            event: "candidate-evaluated",
            timestamp: Date(timeIntervalSince1970: 100),
            phase: "candidate",
            seed: "seed-1",
            generationIndex: 1,
            candidateID: "g1-c0",
            fitness: -4,
            rewardAverage: -2
        )
        let liveEvent = LearningCampaignProgressEvent(
            event: persistedEvent.event,
            timestamp: Date(timeIntervalSince1970: 100.25),
            phase: persistedEvent.phase,
            seed: persistedEvent.seed,
            generationIndex: persistedEvent.generationIndex,
            candidateID: persistedEvent.candidateID,
            fitness: persistedEvent.fitness,
            rewardAverage: persistedEvent.rewardAverage
        )

        metrics.synchronizePersistedEvents([persistedEvent, persistedEvent])
        metrics.append(liveEvent)
        metrics.append(liveEvent)

        #expect(metrics.progressEvents.count == 1)
        #expect(metrics.progressEventsForDisplay == [persistedEvent])
        #expect(metrics.candidateEvaluationCount == 1)

        metrics.reset()

        #expect(metrics.progressEvents.isEmpty)
        #expect(metrics.progressEventsForDisplay.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func distinctWorkUnitsAreNotDeduplicatedWithinTimestampTolerance() throws {
        let metrics = LearningCampaignLiveMetrics()
        let scope = try TrainingWorkScope(runID: "run", generationIndex: 0)
        let first = try TrainingWorkProgress(
            scope: scope,
            phase: .rollout,
            state: .started,
            unit: TrainingWorkUnit(
                kind: .scenario,
                identifier: "6/A/1",
                suiteIndex: 6,
                scenarioID: "A",
                scenarioSeed: 1
            ),
            completedUnitCount: 0,
            totalUnitCount: 2,
            timestamp: Date(timeIntervalSince1970: 100)
        )
        let second = try TrainingWorkProgress(
            scope: scope,
            phase: .rollout,
            state: .started,
            unit: TrainingWorkUnit(
                kind: .scenario,
                identifier: "6/B/2",
                suiteIndex: 6,
                scenarioID: "B",
                scenarioSeed: 2
            ),
            completedUnitCount: 0,
            totalUnitCount: 2,
            timestamp: Date(timeIntervalSince1970: 100.25)
        )
        let persisted = LearningCampaignProgressEvent(
            event: .workProgress(seed: "seed", progress: first),
            timestamp: first.timestamp
        )
        let live = LearningCampaignProgressEvent(
            event: .workProgress(seed: "seed", progress: second),
            timestamp: second.timestamp
        )

        metrics.synchronizePersistedEvents([persisted])
        metrics.append(live)

        #expect(metrics.progressEventsForDisplay == [persisted, live])
    }

    @Test(.timeLimit(.minutes(1)))
    func matchingWorkUnitsAreDeduplicatedWithinTimestampTolerance() throws {
        let metrics = LearningCampaignLiveMetrics()
        let scope = try TrainingWorkScope(runID: "run", generationIndex: 0)
        let unit = try TrainingWorkUnit(
            kind: .controlStep,
            identifier: "6/A/1/control-step",
            suiteIndex: 6,
            scenarioID: "A",
            scenarioSeed: 1
        )
        let persistedProgress = try TrainingWorkProgress(
            scope: scope,
            phase: .rollout,
            state: .advanced,
            unit: unit,
            completedUnitCount: 250,
            totalUnitCount: 1_000,
            timestamp: Date(timeIntervalSince1970: 100)
        )
        let liveProgress = try TrainingWorkProgress(
            scope: scope,
            phase: .rollout,
            state: .advanced,
            unit: unit,
            completedUnitCount: 250,
            totalUnitCount: 1_000,
            timestamp: Date(timeIntervalSince1970: 100.25)
        )
        let persisted = LearningCampaignProgressEvent(
            event: .workProgress(seed: "seed", progress: persistedProgress),
            timestamp: persistedProgress.timestamp
        )
        let live = LearningCampaignProgressEvent(
            event: .workProgress(seed: "seed", progress: liveProgress),
            timestamp: liveProgress.timestamp
        )

        metrics.synchronizePersistedEvents([persisted])
        metrics.append(live)

        #expect(metrics.progressEventsForDisplay == [persisted])
    }

    @Test(.timeLimit(.minutes(1)))
    func generationBestReplacementRemovesMissingAuxiliaryMetrics() {
        let metrics = LearningCampaignLiveMetrics()
        metrics.append(FitnessSummary(
            runID: "run",
            generationIndex: 2,
            candidateID: "g2-c0",
            taskID: "lift",
            scalarFitness: 1,
            rewardAverage: 1,
            taskPassRate: 0.5,
            safetyViolationRate: 0,
            holdTimeRatio: 0.8,
            altitudeErrorRatio: 0.2
        ))
        metrics.append(FitnessSummary(
            runID: "run",
            generationIndex: 2,
            candidateID: "g2-c1",
            taskID: "lift",
            scalarFitness: 2,
            rewardAverage: 2,
            taskPassRate: 0.75,
            safetyViolationRate: 0,
            holdTimeRatio: nil,
            altitudeErrorRatio: nil
        ))

        #expect(metrics.fitnessSamples.map(\.value) == [2])
        #expect(metrics.holdTimeSamples.isEmpty)
        #expect(metrics.altitudeErrorSamples.isEmpty)
    }
}

@MainActor
@Suite("Learning campaign error isolation")
struct LearningCampaignErrorIsolationTests {
    @Test(.timeLimit(.minutes(1)))
    func activeArtifactAutomaticallyReconnectsItsWorker() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("campaign-worker-reconnect-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove test artifact root: \(error)")
            }
        }
        try writeLearningCampaignPlan(to: root)
        let status = LearningCampaignStatus(
            status: "running",
            exitCode: 0,
            startedAt: "2026-07-16T00:00:00Z",
            finishedAt: ""
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(status).write(
            to: root.appendingPathComponent("campaign-status.json"),
            options: [.atomic]
        )
        let runID = TrainingRunID("reconnected-from-artifact")
        let handle = ArtifactReconnectTrainingRunHandle(
            runID: runID,
            artifactRoot: root
        )
        let commandSystem = CommandSystem(
            modelStore: ManasMLXModelStore(),
            trainingRunExecutor: ArtifactReconnectTrainingRunExecutor(handle: handle)
        )
        let model = SimulationViewModel(
            logStore: UILogStore(buffer: UILogBuffer()),
            commandSystem: commandSystem
        )
        model.learningCampaignArtifactDirectory = root.path

        model.loadLearningCampaignArtifacts()
        await model.waitForLearningCampaignArtifactLoad()
        await model.waitForLearningCampaignWorkerReconnect()

        #expect(model.isLearningCampaignRunning)
        #expect(model.learningCampaignExecutionSnapshot.runID == runID)
        #expect(model.learningCampaignCurrentPhase == "reconnected")

        model.stopLearningCampaign()
        for _ in 0..<1_000 where model.isLearningCampaignRunning {
            await Task.yield()
        }
        #expect(!model.isLearningCampaignRunning)
    }

    @Test(.timeLimit(.minutes(1)))
    func activeArtifactFailsAfterWorkerRegistrationRetryLimit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("campaign-worker-missing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove test artifact root: \(error)")
            }
        }
        try writeLearningCampaignPlan(to: root)
        let status = LearningCampaignStatus(
            status: "running",
            exitCode: 0,
            startedAt: "2026-07-16T00:00:00Z",
            finishedAt: ""
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(status).write(
            to: root.appendingPathComponent("campaign-status.json"),
            options: [.atomic]
        )
        let commandSystem = CommandSystem(
            modelStore: ManasMLXModelStore(),
            trainingRunExecutor: MissingArtifactReconnectTrainingRunExecutor()
        )
        let model = SimulationViewModel(
            logStore: UILogStore(buffer: UILogBuffer()),
            commandSystem: commandSystem
        )
        model.learningCampaignArtifactDirectory = root.path

        for _ in 0..<5 {
            model.loadLearningCampaignArtifacts()
            await model.waitForLearningCampaignArtifactLoad()
            await model.waitForLearningCampaignWorkerReconnect()
        }

        #expect(model.learningCampaignCurrentPhase == "failed")
        #expect(model.learningCampaignError?.contains("workerRegistrationTimedOut") == true)
        #expect(model.learningCampaignError?.contains(root.path) == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func inputFailureSupersedesOlderExecutionAndArtifactFailures() {
        #expect(LearningCampaignErrorResolver.resolve(
            input: "new input failure",
            execution: "old execution failure",
            artifact: "older artifact failure"
        ) == "new input failure")
        #expect(LearningCampaignErrorResolver.resolve(
            input: nil,
            execution: "execution failure",
            artifact: "artifact failure"
        ) == "execution failure")
        #expect(LearningCampaignErrorResolver.resolve(
            input: nil,
            execution: nil,
            artifact: "artifact failure"
        ) == "artifact failure")
    }

    @Test(.timeLimit(.minutes(1)))
    func successfulArtifactPollingDoesNotClearAnOperationError() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("campaign-error-isolation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove test artifact root: \(error)")
            }
        }
        try writeLearningCampaignPlan(to: root)

        let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
        model.learningCampaignArtifactDirectory = root.path
        model.learningCampaignError = "launch validation failed"
        model.loadLearningCampaignArtifacts()
        await model.waitForLearningCampaignArtifactLoad()

        #expect(model.learningCampaignState != nil)
        #expect(model.learningCampaignError == "launch validation failed")
    }

    @Test(.timeLimit(.minutes(1)))
    func artifactPollingCannotMoveDisplayedProgressBackward() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("campaign-progress-monotonic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove test artifact root: \(error)")
            }
        }
        try writeLearningCampaignPlan(to: root)
        let event = LearningCampaignProgressEvent(
            event: "candidate-evaluated",
            timestamp: Date(timeIntervalSince1970: 100),
            phase: "candidate",
            seed: "seed-1",
            generationIndex: 0,
            candidateID: "g0-c0",
            fitness: -4,
            rewardAverage: -2
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var progressLine = try encoder.encode(event)
        progressLine.append(0x0A)
        try progressLine.write(
            to: root.appendingPathComponent("progress.jsonl"),
            options: .atomic
        )

        let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
        model.learningCampaignArtifactDirectory = root.path
        model.learningCampaignProgressFraction = 0.8
        model.loadLearningCampaignArtifacts()
        await model.waitForLearningCampaignArtifactLoad()

        #expect(model.learningCampaignState?.campaignProgressFraction == 0.5)
        #expect(model.learningCampaignProgressFraction == 0.8)
    }
}

private enum ArtifactReconnectTrainingRunError: Error {
    case unsupported
}

private struct MissingArtifactReconnectTrainingRunExecutor: AnyTrainingRunExecuting {
    func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        throw ArtifactReconnectTrainingRunError.unsupported
    }

    func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        throw ArtifactReconnectTrainingRunError.unsupported
    }

    func reconnect(artifactRoot: URL) async throws -> (any TrainingRunHandle)? {
        nil
    }

    func continuationSelection(from artifactRoot: URL) throws -> TrainingContinuationSelection {
        throw ArtifactReconnectTrainingRunError.unsupported
    }

    func validate(_ request: TrainingRunRequest) throws {}

    func validate(_ request: TrainingResumeRequest) throws {}
}

private struct ArtifactReconnectTrainingRunExecutor: AnyTrainingRunExecuting {
    let handle: ArtifactReconnectTrainingRunHandle

    func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        throw ArtifactReconnectTrainingRunError.unsupported
    }

    func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        throw ArtifactReconnectTrainingRunError.unsupported
    }

    func reconnect(artifactRoot: URL) async throws -> (any TrainingRunHandle)? {
        guard artifactRoot.standardizedFileURL == handle.artifactRoot.standardizedFileURL else {
            return nil
        }
        return handle
    }

    func continuationSelection(from artifactRoot: URL) throws -> TrainingContinuationSelection {
        throw ArtifactReconnectTrainingRunError.unsupported
    }

    func validate(_ request: TrainingRunRequest) throws {}

    func validate(_ request: TrainingResumeRequest) throws {}
}

private final class ArtifactReconnectTrainingRunHandle: TrainingRunHandle, Sendable {
    let runID: TrainingRunID
    let artifactRoot: URL
    let progress = Progress(totalUnitCount: 1)
    let events = AsyncStream<TrainingRunEvent> { _ in }

    init(runID: TrainingRunID, artifactRoot: URL) {
        self.runID = runID
        self.artifactRoot = artifactRoot
    }

    func cancel() {}

    func wait() async throws -> TrainingRunSummary {
        try await Task.sleep(for: .seconds(30))
        return TrainingRunSummary(
            runID: runID,
            artifactRoot: artifactRoot,
            terminalState: .failed,
            failureReasons: ["test timeout"]
        )
    }

    func shutdown() async {}
}

private func writeLearningCampaignPlan(to root: URL) throws {
    let plan = LearningCampaignPlan(
        artifactRoot: root.path,
        task: "singleLift",
        searchSuites: ["6"],
        searchEpisodes: 1,
        acceptanceSuites: ["6"],
        acceptanceEpisodes: 1,
        workers: 1,
        population: 2,
        generations: 1,
        eliteCount: 1,
        candidateEvaluationConcurrency: 1,
        cutPeriodSteps: 2,
        seeds: ["seed-1"],
        sourceCheckpoint: nil,
        robotManifest: nil,
        variation: "test",
        searchStrategy: "genetic",
        mutationRate: 0.02,
        mutationNoiseScale: 0.01,
        bootstrapSuite: "6",
        bootstrapEpisodes: 1,
        bootstrapSequence: 8,
        bootstrapEpochs: 1,
        bootstrapMaxBatches: 1,
        bootstrapLearningRate: 0.001,
        bootstrapRepairAttempts: nil,
        verifyParentTask: true,
        resumeEnabled: false,
        resourceSampleSeconds: nil,
        artifactRetentionPolicy: .compact,
        availableDiskBytes: 1_000_000,
        requiredDiskBytes: 1_000,
        plannedCandidateEvaluations: 2,
        plannedRegressionRollouts: 2,
        plannedRegressionEpisodes: 2
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(plan).write(
        to: root.appendingPathComponent("learning-campaign-plan.json"),
        options: .atomic
    )
}

private func makeFitness(
    generationIndex: Int,
    candidateID: String,
    scalarFitness: Double,
    rewardAverage: Double,
    taskPassRate: Double
) -> FitnessSummary {
    FitnessSummary(
        runID: "run",
        generationIndex: generationIndex,
        candidateID: candidateID,
        taskID: "lift",
        scalarFitness: scalarFitness,
        rewardAverage: rewardAverage,
        taskPassRate: taskPassRate,
        safetyViolationRate: 0,
        holdTimeRatio: taskPassRate,
        altitudeErrorRatio: 1 - taskPassRate
    )
}

private func makeProgressEvent(
    generationIndex: Int,
    candidateID: String,
    fitness: Double,
    rewardAverage: Double,
    taskPassRate: Double
) -> TrainingRunProgressEvent {
    TrainingRunProgressEvent(
        timestamp: Date(timeIntervalSince1970: Double(generationIndex)),
        event: "candidate-evaluated",
        phase: "candidate",
        seed: "seed-1",
        generationIndex: generationIndex,
        candidateID: candidateID,
        fitness: fitness,
        rewardAverage: rewardAverage,
        taskPassRate: taskPassRate,
        safetyViolationRate: 0,
        holdTimeRatio: taskPassRate,
        altitudeErrorRatio: 1 - taskPassRate,
        workerThroughput: 10,
        gpuAcceleration: true,
        tensorWorldBatch: true,
        tensorSummary: true,
        vectorizedPopulationSize: 100,
        vectorizedWorldCount: 100,
        vectorizedHistoryLength: 32,
        vectorizedObservationDimension: 64,
        vectorizedActionDimension: 4,
        failureReasons: []
    )
}
