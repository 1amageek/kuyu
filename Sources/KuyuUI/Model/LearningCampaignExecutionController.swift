import Foundation
import KuyuMLXCampaignContracts
import KuyuTraining
import Logging
import Observation

struct LearningCampaignExecutionContext: Sendable {
    let taskID: String
    let suiteCount: Int
    let episodesPerSuite: Int
}

enum LearningCampaignExecutionError: Error, Equatable {
    case alreadyRunning
    case workerRegistrationTimedOut(path: String)
}

@Observable
@MainActor
final class LearningCampaignExecutionController {
    private enum AbandonedLaunchDisposition {
        case cancelWorker
        case detachObserver
    }

    private enum PendingTerminalOutcome {
        case summary(TrainingRunSummary)
        case failure(String)
    }

    var progressFraction: Double = 0
    var currentPhase: String = "idle"
    var readiness: LearningCampaignReadinessState = .idle
    var latestEvent: String?
    var runLog: [LearningCampaignRunLogRecord] = []
    var liveFitnessSamples: [MetricSample] {
        get { liveMetrics.fitnessSamples }
        set { liveMetrics.fitnessSamples = newValue }
    }
    var liveRewardSamples: [MetricSample] {
        get { liveMetrics.rewardSamples }
        set { liveMetrics.rewardSamples = newValue }
    }
    var liveTaskPassSamples: [MetricSample] {
        get { liveMetrics.taskPassSamples }
        set { liveMetrics.taskPassSamples = newValue }
    }
    var liveHoldTimeSamples: [MetricSample] {
        get { liveMetrics.holdTimeSamples }
        set { liveMetrics.holdTimeSamples = newValue }
    }
    var liveAltitudeErrorSamples: [MetricSample] {
        get { liveMetrics.altitudeErrorSamples }
        set { liveMetrics.altitudeErrorSamples = newValue }
    }
    var liveEpisodeSamples: [MetricSample] {
        get { liveMetrics.episodeSamples }
        set { liveMetrics.episodeSamples = newValue }
    }
    var liveCandidateEvaluationCount: Int {
        get { liveMetrics.candidateEvaluationCount }
        set { liveMetrics.candidateEvaluationCount = newValue }
    }
    var liveProgressEvents: [LearningCampaignProgressEvent] {
        liveMetrics.progressEvents
    }
    var progressEventsForDisplay: [LearningCampaignProgressEvent] {
        liveMetrics.progressEventsForDisplay
    }
    var isRunning = false
    var lastRunnerEventAt: Date?
    var error: String?
    private(set) var terminalSummary: TrainingRunSummary?
    private(set) var activeRunID: TrainingRunID?
    private(set) var activeArtifactRoot: URL?

    private var executor: any LearningCampaignRunCommanding
    private let logStore: UILogStore
    private let liveMetrics = LearningCampaignLiveMetrics()
    private var persistedProgressFraction: Double?
    private var launchTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var handle: (any TrainingRunHandle)?
    private var pendingTerminalOutcome: PendingTerminalOutcome?
    private var executionID: UInt64 = 0
    private var clearAfterCleanup = false
    private var abandonedLaunchDispositions: [UInt64: AbandonedLaunchDisposition] = [:]

    init(executor: any LearningCampaignRunCommanding, logStore: UILogStore) {
        self.executor = executor
        self.logStore = logStore
    }

    var hasActiveHandle: Bool {
        handle != nil
    }

    var canAdoptPersistedPresentation: Bool {
        !isRunning
            && activeRunID == nil
            && terminalSummary == nil
            && pendingTerminalOutcome == nil
    }

    var snapshot: LearningCampaignExecutionSnapshot {
        LearningCampaignExecutionSnapshot(
            runID: terminalSummary?.runID ?? activeRunID,
            artifactRoot: terminalSummary?.artifactRoot ?? activeArtifactRoot,
            isRunning: isRunning,
            progressFraction: progressFraction,
            phase: currentPhase,
            latestEvent: latestEvent,
            error: error,
            terminalSummary: terminalSummary
        )
    }

    func replaceExecutor(_ executor: any LearningCampaignRunCommanding) -> Bool {
        guard !isRunning,
              handle == nil,
              launchTask == nil,
              eventTask == nil,
              completionTask == nil,
              cleanupTask == nil else {
            return false
        }
        self.executor = executor
        return true
    }

    func start(
        request: TrainingRunRequest,
        continuationArtifactRoot: URL?,
        initialLogRecord: LearningCampaignRunLogRecord,
        context: LearningCampaignExecutionContext
    ) throws {
        guard !isRunning,
              handle == nil,
              launchTask == nil,
              eventTask == nil,
              completionTask == nil,
              cleanupTask == nil else {
            throw LearningCampaignExecutionError.alreadyRunning
        }

        liveMetrics.updateContext(context)
        executionID &+= 1
        let launchedExecutionID = executionID
        let executor = self.executor
        isRunning = true
        error = nil
        terminalSummary = nil
        pendingTerminalOutcome = nil
        activeRunID = request.runID
        activeArtifactRoot = request.artifactRoot
        persistedProgressFraction = nil
        progressFraction = 0
        currentPhase = "starting"
        readiness = .ready(message: "Campaign launched with validated config.")
        latestEvent = nil
        lastRunnerEventAt = nil
        runLog = [initialLogRecord]
        liveMetrics.reset()

        launchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let handle: any TrainingRunHandle
                if let continuationArtifactRoot {
                    handle = try await executor.resumeTrainingRun(request: TrainingResumeRequest(
                        runID: request.runID,
                        source: .artifactRoot(continuationArtifactRoot),
                        destinationArtifactRoot: request.artifactRoot,
                        projectRoot: request.projectRoot,
                        taskProfileID: request.taskProfileID,
                        policyContract: request.policyContract,
                        actionContract: request.actionContract,
                        seedCount: request.seedCount,
                        populationSize: request.populationSize,
                        generationLimit: request.generationLimit,
                        configuration: request.configuration
                    ))
                } else {
                    handle = try await executor.startTrainingRun(request: request)
                }

                guard !Task.isCancelled, self.executionID == launchedExecutionID else {
                    let disposition = self.abandonedLaunchDispositions.removeValue(
                        forKey: launchedExecutionID
                    ) ?? .cancelWorker
                    switch disposition {
                    case .cancelWorker:
                        handle.cancel()
                        await handle.shutdown()
                    case .detachObserver:
                        await handle.detach()
                    }
                    self.finishCancelledLaunch(executionID: launchedExecutionID)
                    return
                }
                self.handle = handle
                self.launchTask = nil
                self.progressFraction = self.boundedProgress(handle.progress.fractionCompleted)
                self.startEventMonitoring(handle: handle, executionID: launchedExecutionID)
                self.startCompletionMonitoring(handle: handle, executionID: launchedExecutionID)
            } catch is CancellationError {
                self.finishCancelledLaunch(executionID: launchedExecutionID)
            } catch {
                self.finishFailedLaunch(
                    error,
                    taskID: request.taskProfileID,
                    executionID: launchedExecutionID
                )
            }
        }
    }

    func reconnect(artifactRoot: URL) async throws -> Bool {
        guard !isRunning,
              handle == nil,
              launchTask == nil,
              eventTask == nil,
              completionTask == nil,
              cleanupTask == nil else {
            throw LearningCampaignExecutionError.alreadyRunning
        }

        executionID &+= 1
        let reconnectedExecutionID = executionID
        isRunning = true
        error = nil
        terminalSummary = nil
        pendingTerminalOutcome = nil
        activeRunID = nil
        activeArtifactRoot = artifactRoot
        currentPhase = "reconnecting"
        latestEvent = "Locating the active training worker"

        do {
            let reconnectedHandle = try await executor.reconnectTrainingRun(
                artifactRoot: artifactRoot
            )
            guard executionID == reconnectedExecutionID else {
                await reconnectedHandle?.detach()
                return false
            }
            guard let reconnectedHandle else {
                isRunning = false
                activeArtifactRoot = nil
                currentPhase = "stale"
                latestEvent = "Waiting for training worker registration"
                readiness = .idle
                return false
            }

            handle = reconnectedHandle
            activeRunID = reconnectedHandle.runID
            progressFraction = boundedProgress(reconnectedHandle.progress.fractionCompleted)
            currentPhase = "reconnected"
            latestEvent = "Monitoring the active training worker"
            readiness = .ready(message: "Campaign worker reconnected.")
            startEventMonitoring(
                handle: reconnectedHandle,
                executionID: reconnectedExecutionID
            )
            startCompletionMonitoring(
                handle: reconnectedHandle,
                executionID: reconnectedExecutionID
            )
            return true
        } catch {
            guard executionID == reconnectedExecutionID else { return false }
            isRunning = false
            activeRunID = nil
            activeArtifactRoot = nil
            currentPhase = "failed"
            latestEvent = "Training worker reconnection failed"
            self.error = String(describing: error)
            readiness = .blocked(message: String(describing: error))
            throw error
        }
    }

    func stop() {
        if pendingTerminalOutcome != nil {
            currentPhase = "finalizing"
            latestEvent = "Publishing terminal campaign outcome"
            return
        }
        if cleanupTask != nil {
            return
        }
        let pendingLaunch = launchTask
        let pendingEvents = eventTask
        let pendingCompletion = completionTask
        let stoppedHandle = handle
        guard isRunning || pendingLaunch != nil || pendingEvents != nil || pendingCompletion != nil || stoppedHandle != nil else {
            return
        }

        let launchedExecutionID = executionID
        if pendingLaunch != nil {
            abandonedLaunchDispositions[launchedExecutionID] = .cancelWorker
        }
        executionID &+= 1
        let stoppedExecutionID = executionID
        pendingLaunch?.cancel()
        stoppedHandle?.cancel()
        pendingEvents?.cancel()
        pendingCompletion?.cancel()
        isRunning = true
        currentPhase = "cancelling"
        latestEvent = "Waiting for campaign shutdown"

        cleanupTask = Task { @MainActor [weak self, pendingLaunch, pendingEvents, pendingCompletion, stoppedHandle] in
            if let stoppedHandle {
                await stoppedHandle.shutdown()
            }
            await pendingEvents?.value
            await pendingCompletion?.value
            await pendingLaunch?.value

            guard let self, self.executionID == stoppedExecutionID else { return }
            self.launchTask = nil
            self.eventTask = nil
            self.completionTask = nil
            self.handle = nil
            self.cleanupTask = nil
            self.abandonedLaunchDispositions.removeValue(forKey: launchedExecutionID)
            self.isRunning = false
            if self.clearAfterCleanup {
                self.clearAfterCleanup = false
                self.resetState()
            } else {
                self.currentPhase = "cancelled"
                self.latestEvent = "Campaign cancelled"
                self.readiness = .idle
            }
        }
    }

    func clear() {
        if isRunning || handle != nil || launchTask != nil || eventTask != nil || completionTask != nil || cleanupTask != nil {
            clearAfterCleanup = true
            stop()
            return
        }
        resetState()
    }

    func shutdown() async {
        if let cleanupTask {
            await cleanupTask.value
            return
        }
        let detachedExecutionID = executionID
        let pendingLaunch = launchTask
        let detachedHandle = handle
        if pendingLaunch != nil {
            abandonedLaunchDispositions[detachedExecutionID] = .detachObserver
        }
        executionID &+= 1
        pendingLaunch?.cancel()
        eventTask?.cancel()
        completionTask?.cancel()
        launchTask = nil
        eventTask = nil
        completionTask = nil
        handle = nil
        pendingTerminalOutcome = nil
        isRunning = false
        currentPhase = "detached"
        latestEvent = "Campaign continues in the training worker"
        await detachedHandle?.detach()
    }

    func synchronizePersistedState(_ state: LearningCampaignRunStoreState?) {
        if let state,
           let activeArtifactRoot,
           !LearningCampaignMonitorProjection.sameLocation(state.artifactDirectory, activeArtifactRoot) {
            return
        }
        persistedProgressFraction = state.map { min(1, max(0, $0.campaignProgressFraction)) }
        liveMetrics.synchronizePersistedEvents(state?.progressEvents ?? [])
        if let persistedProgressFraction {
            let upperBound = isRunning ? 0.999 : 1
            progressFraction = min(upperBound, max(progressFraction, persistedProgressFraction))
        }
        if isRunning, let state {
            currentPhase = state.latestEvent?.phase
                ?? state.progress.lifecycleStage.rawValue
            if let message = state.latestEvent?.message {
                latestEvent = message
            }
        }
    }

    func failWorkerRegistration(artifactRoot: URL) {
        guard !isRunning, handle == nil, launchTask == nil else { return }
        let failure = LearningCampaignExecutionError.workerRegistrationTimedOut(
            path: artifactRoot.path
        )
        activeArtifactRoot = artifactRoot
        currentPhase = "failed"
        latestEvent = "Training worker registration timed out"
        error = String(describing: failure)
        readiness = .blocked(message: String(describing: failure))
    }

    func replaceRunLog(_ records: [LearningCampaignRunLogRecord]) {
        runLog = records
    }

    func updateContext(_ context: LearningCampaignExecutionContext) {
        liveMetrics.updateContext(context)
    }

    func appendLiveProgressEvent(_ progressEvent: TrainingRunProgressEvent) {
        liveMetrics.append(progressEvent)
    }

    func appendLiveProgressRecord(_ progressRecord: LearningCampaignProgressEvent) {
        liveMetrics.append(progressRecord)
    }

    func appendLiveMetricSamples(_ fitness: FitnessSummary) {
        liveMetrics.append(fitness)
    }

    private func startEventMonitoring(handle: any TrainingRunHandle, executionID: UInt64) {
        eventTask?.cancel()
        eventTask = Task { @MainActor [weak self, handle] in
            for await event in handle.events {
                guard !Task.isCancelled else { return }
                guard self?.executionID == executionID else { return }
                self?.apply(event, progress: handle.progress)
            }
        }
    }

    private func startCompletionMonitoring(handle: any TrainingRunHandle, executionID: UInt64) {
        completionTask?.cancel()
        completionTask = Task { @MainActor [weak self, handle] in
            do {
                let summary = try await handle.wait()
                guard !Task.isCancelled,
                      self?.executionID == executionID,
                      self?.handle?.runID == handle.runID else {
                    return
                }
                self?.pendingTerminalOutcome = .summary(summary)
                await handle.shutdown()
                guard !Task.isCancelled,
                      self?.executionID == executionID,
                      self?.handle?.runID == handle.runID else {
                    return
                }
                let pendingEvents = self?.eventTask
                pendingEvents?.cancel()
                await pendingEvents?.value
                guard !Task.isCancelled,
                      self?.executionID == executionID,
                      self?.handle?.runID == handle.runID else {
                    return
                }
                self?.finish(summary, executionID: executionID)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      self?.executionID == executionID,
                      self?.handle?.runID == handle.runID else {
                    return
                }
                self?.pendingTerminalOutcome = .failure("\(error)")
                await handle.shutdown()
                guard !Task.isCancelled,
                      self?.executionID == executionID,
                      self?.handle?.runID == handle.runID else {
                    return
                }
                let pendingEvents = self?.eventTask
                pendingEvents?.cancel()
                await pendingEvents?.value
                guard !Task.isCancelled,
                      self?.executionID == executionID,
                      self?.handle?.runID == handle.runID else {
                    return
                }
                self?.finishFailedRun(error, executionID: executionID)
            }
        }
    }

    private func apply(_ event: TrainingRunEvent, progress: Progress) {
        lastRunnerEventAt = Date()
        progressFraction = boundedProgress(progress.fractionCompleted)
        switch event {
        case .progress(let progressEvent):
            appendLiveProgressEvent(progressEvent)
            if let progressFraction = progressEvent.progressFraction {
                self.progressFraction = boundedProgress(progressFraction)
            }
            if let phase = progressEvent.phase {
                currentPhase = phase
            }
            if let message = progressEvent.message {
                latestEvent = message
            }
        case .log(let logEvent):
            appendRunLogRecord(LearningCampaignRunLogFormatter.entry(from: logEvent, progress: progress))
            currentPhase = logEvent.phase
            latestEvent = logEvent.message
        case .started(let manifest):
            currentPhase = "started"
            latestEvent = "Run \(manifest.runID) started"
            appendRunLogRecord(LearningCampaignRunLogFormatter.entry(from: TrainingRunLogEvent(
                level: .info,
                phase: "started",
                message: "Training run started",
                metadata: ["runID": manifest.runID]
            ), progress: progress))
        case .iterationStarted(let iteration):
            currentPhase = "iteration \(iteration)"
            latestEvent = "Iteration \(iteration) started"
        case .suiteCompleted(let iteration, _, let score):
            currentPhase = "iteration \(iteration)"
            latestEvent = String(format: "Suite score %.3f", score)
        case .datasetExported(let iteration, let directory, let count):
            currentPhase = "dataset"
            latestEvent = "Iteration \(iteration) exported \(count) samples"
            appendRunLogRecord(LearningCampaignRunLogFormatter.entry(from: TrainingRunLogEvent(
                level: .info,
                phase: "dataset",
                message: "Dataset exported",
                metadata: ["iteration": "\(iteration)", "directory": directory, "count": "\(count)"]
            ), progress: progress))
        case .trainingCompleted(let iteration, let result):
            currentPhase = "training"
            latestEvent = String(format: "Iteration \(iteration) loss %.6f", result.finalLoss)
        case .reinforcementTrainingCompleted(let iteration, let result):
            currentPhase = "reinforcement"
            latestEvent = String(format: "Iteration \(iteration) reward %.3f", result.rewardAverage)
        case .convergenceUpdated(let summary):
            currentPhase = "convergence"
            latestEvent = summary.accepted ? "Checkpoint accepted" : summary.reason
        case .completed(let result):
            currentPhase = result.manifest.terminalState.rawValue
            latestEvent = result.checkpointDecision.state.rawValue
        }
    }

    private func finishCancelledLaunch(executionID: UInt64) {
        guard self.executionID == executionID else { return }
        launchTask = nil
        handle = nil
        isRunning = false
        if currentPhase == "starting" {
            currentPhase = "cancelled"
        }
    }

    private func finish(_ summary: TrainingRunSummary, executionID: UInt64) {
        guard self.executionID == executionID else { return }
        terminalSummary = summary
        pendingTerminalOutcome = nil
        launchTask = nil
        eventTask = nil
        completionTask = nil
        handle = nil
        isRunning = false
        let observedProgress = min(1, max(progressFraction, persistedProgressFraction ?? 0))
        switch summary.terminalState {
        case .completed, .rejected:
            progressFraction = 1
        case .failed, .cancelled, .running:
            progressFraction = observedProgress
        }

        let reasons = summary.failureReasons.isEmpty
            ? "No failure reason was recorded."
            : summary.failureReasons.joined(separator: ", ")
        switch summary.terminalState {
        case .completed:
            currentPhase = "completed"
            latestEvent = "Campaign completed"
            readiness = .ready(message: "Campaign completed and published its terminal summary.")
            error = nil
        case .rejected:
            currentPhase = "rejected"
            latestEvent = "Campaign completed without an accepted checkpoint"
            readiness = .blocked(message: reasons)
            error = reasons
        case .failed:
            currentPhase = "failed"
            latestEvent = "Campaign failed"
            readiness = .blocked(message: reasons)
            error = reasons
        case .cancelled:
            currentPhase = "cancelled"
            latestEvent = "Campaign cancelled"
            readiness = .idle
            error = nil
        case .running:
            let message = "Training run returned a non-terminal summary."
            currentPhase = "failed"
            latestEvent = message
            readiness = .blocked(message: message)
            error = message
        }
        appendRunLogRecord(LearningCampaignRunLogRecord(
            category: .lifecycle,
            level: summary.terminalState == .completed ? .success : .warning,
            phase: currentPhase,
            title: latestEvent ?? "Campaign finished",
            detail: summary.failureReasons.isEmpty ? "" : reasons,
            metadata: [
                "run \(summary.runID)",
                "generations \(summary.generationCount)",
                "candidates \(summary.candidateCount)",
                "artifact \(summary.artifactRoot.path)"
            ]
        ))
        completeDeferredClearIfNeeded()
    }

    private func finishFailedRun(_ failure: any Error, executionID: UInt64) {
        guard self.executionID == executionID else { return }
        launchTask = nil
        eventTask = nil
        completionTask = nil
        handle = nil
        isRunning = false
        pendingTerminalOutcome = nil
        let message = "\(failure)"
        error = message
        currentPhase = "failed"
        latestEvent = message
        readiness = .blocked(message: message)
        appendRunLogRecord(LearningCampaignRunLogRecord(
            category: .diagnostics,
            level: .failure,
            phase: "failed",
            title: "Campaign execution failed",
            detail: message
        ))
        completeDeferredClearIfNeeded()
    }

    private func finishFailedLaunch(
        _ error: any Error,
        taskID: String,
        executionID: UInt64
    ) {
        guard self.executionID == executionID else { return }
        launchTask = nil
        handle = nil
        isRunning = false
        self.error = "\(error)"
        currentPhase = "failed"
        readiness = .blocked(message: "\(error)")
        var metadata = [
            "action": "startLearningCampaign",
            "task": taskID,
            "error": "\(error)"
        ]
        metadata["phase"] = currentPhase
        logStore.emit(UILogEntry(
            timestamp: Date(),
            level: .error,
            label: "kuyu.ui",
            message: "Learning campaign launch failed",
            metadata: metadata
        ))
    }

    private func boundedProgress(_ fallback: Double) -> Double {
        let observed = max(progressFraction, fallback, persistedProgressFraction ?? 0)
        return min(isRunning ? 0.999 : 1, max(0, observed))
    }

    private func appendRunLogRecord(_ entry: LearningCampaignRunLogRecord) {
        runLog.append(entry)
        let maximumEntryCount = 500
        if runLog.count > maximumEntryCount {
            runLog.removeFirst(runLog.count - maximumEntryCount)
        }
    }

    private func completeDeferredClearIfNeeded() {
        guard clearAfterCleanup else { return }
        clearAfterCleanup = false
        resetState()
    }

    private func resetState() {
        persistedProgressFraction = nil
        progressFraction = 0
        currentPhase = "idle"
        readiness = .idle
        latestEvent = nil
        runLog = []
        error = nil
        terminalSummary = nil
        pendingTerminalOutcome = nil
        activeRunID = nil
        activeArtifactRoot = nil
        lastRunnerEventAt = nil
        liveMetrics.reset()
    }

}
