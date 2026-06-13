import Foundation

struct TrainingMonitorSnapshot: Sendable, Equatable {
    enum Health: String, Sendable, Equatable {
        case idle
        case healthy
        case attention
        case stale
        case failed
        case complete

        var label: String {
            switch self {
            case .idle:
                return "idle"
            case .healthy:
                return "healthy"
            case .attention:
                return "attention"
            case .stale:
                return "stale"
            case .failed:
                return "failed"
            case .complete:
                return "complete"
            }
        }
    }

    enum AlertSeverity: Int, Sendable, Equatable {
        case info
        case warning
        case critical
    }

    struct Alert: Identifiable, Sendable, Equatable {
        let id: String
        let severity: AlertSeverity
        let title: String
        let detail: String
    }

    private struct StalenessPolicy: Sendable, Equatable {
        let eventStream: TimeInterval
        let artifactChange: TimeInterval
        let artifactLoad: TimeInterval
        let candidate: TimeInterval
    }

    let health: Health
    let statusLabel: String
    let phase: String
    let latestEvent: String?
    let progressFraction: Double
    let generationText: String
    let candidateText: String
    let estimatedRemainingText: String
    let eventAgeText: String
    let artifactAgeText: String
    let candidateAgeText: String
    let eventStreamStatus: String
    let artifactMonitorStatus: String
    let artifactLoadStatus: String
    let artifactRootLabel: String
    let acceleratorLabel: String
    let gpuEvidenceLabel: String
    let throughputText: String
    let parallelismText: String
    let runLogRetentionText: String
    let alerts: [Alert]

    @MainActor
    init(model: SimulationViewModel, now: Date = Date()) {
        let state = model.learningCampaignState
        let progressEvents = model.learningCampaignProgressEventsForDisplay
        let latestProgressRecord = progressEvents.last
        let latestCandidateRecord = progressEvents.last { $0.event == "candidate-evaluated" }
        let latestProgressEventDate = latestProgressRecord.flatMap { Self.parseISOTimestamp($0.timestamp) }
        let latestCandidateDate = latestCandidateRecord.flatMap { Self.parseISOTimestamp($0.timestamp) }
        let lastRunnerEventAt = model.learningCampaignLastRunnerEventAt ?? latestProgressEventDate
        let latestBatch = state?.latestVectorizedBatch
        let latestThroughput = latestCandidateRecord?.workerThroughput.flatMap(Self.finitePositive)
            ?? latestBatch.flatMap(Self.throughput(batch:))
        let plannedCandidates = state?.plannedCandidateEvaluationCount ?? 0
        let completedCandidates = state?.liveCandidateEvaluationCount ?? model.learningCampaignLiveCandidateEvaluationCount
        let remainingCandidates = max(0, plannedCandidates - completedCandidates)
        let isRunning = model.isLearningCampaignRunning
        let status = state?.statusLabel ?? (isRunning ? "running" : "idle")
        let normalizedStatus = status.lowercased()
        let progress = state?.campaignProgressFraction ?? model.learningCampaignProgressFraction
        let primaryIssue = state?.primaryFailureReason
            ?? model.lastPostRegressionGate?.primaryRejectReason
            ?? model.learningCampaignError
        let eventAge = lastRunnerEventAt.map { now.timeIntervalSince($0) }
        let artifactAge = model.learningCampaignLastArtifactLoadChangedAt.map { now.timeIntervalSince($0) }
        let artifactLoadAge = model.learningCampaignLastArtifactLoadStartedAt.map { now.timeIntervalSince($0) }
        let candidateAge = latestCandidateDate.map { now.timeIntervalSince($0) }
        let stalenessPolicy = Self.stalenessPolicy(
            state: state,
            latestThroughput: latestThroughput,
            hasLoadedArtifactState: model.learningCampaignLastArtifactLoadChangedAt != nil
        )
        let gpuActivity = LearningCampaignGPUActivitySnapshot(
            batches: state?.vectorizedBatches ?? [],
            progressEvents: progressEvents,
            acceleratorLabel: state?.latestAcceleratorDevice ?? state?.accelerator?.acceleratorLabel,
            currentAllocatedBytes: MetalGPUUsageProbe.currentAllocatedBytes,
            recommendedMaxWorkingSetBytes: MetalGPUUsageProbe.recommendedMaxWorkingSetBytes
        )

        self.statusLabel = status
        self.phase = model.learningCampaignCurrentPhase
        self.latestEvent = model.learningCampaignLatestEvent
        self.progressFraction = progress
        self.generationText = Self.generationText(state: state)
        self.candidateText = Self.candidateText(
            completed: completedCandidates,
            planned: plannedCandidates
        )
        self.estimatedRemainingText = Self.estimatedRemainingText(
            remainingCandidates: remainingCandidates,
            throughput: latestThroughput
        )
        self.eventAgeText = Self.ageText(eventAge)
        self.artifactAgeText = Self.ageText(artifactAge)
        self.candidateAgeText = Self.ageText(candidateAge)
        self.eventStreamStatus = Self.eventStreamStatus(
            isRunning: isRunning,
            age: eventAge,
            policy: stalenessPolicy
        )
        self.artifactMonitorStatus = model.learningCampaignMonitorEnabled ? "watching" : "off"
        self.artifactLoadStatus = Self.artifactLoadStatus(
            startedAt: model.learningCampaignLastArtifactLoadStartedAt,
            finishedAt: model.learningCampaignLastArtifactLoadFinishedAt,
            failureCount: model.learningCampaignArtifactLoadFailureCount,
            now: now,
            policy: stalenessPolicy
        )
        self.artifactRootLabel = Self.artifactRootLabel(
            state: state,
            configuredPath: model.learningCampaignArtifactDirectory
        )
        self.acceleratorLabel = gpuActivity.acceleratorLabel
        self.gpuEvidenceLabel = Self.gpuEvidenceLabel(activity: gpuActivity)
        self.throughputText = Self.throughputText(latestThroughput)
        self.parallelismText = state?.actualParallelismLabel
            ?? "\(model.learningCampaignCandidateEvaluationConcurrency) requested"
        self.runLogRetentionText = "\(model.learningCampaignRunLog.count)/500 UI log, \(progressEvents.count)/4000 events"

        var generatedAlerts = Self.makeAlerts(
            isRunning: isRunning,
            normalizedStatus: normalizedStatus,
            primaryIssue: primaryIssue,
            eventAge: eventAge,
            artifactAge: artifactAge,
            artifactLoadAge: artifactLoadAge,
            candidateAge: candidateAge,
            stalenessPolicy: stalenessPolicy,
            model: model,
            state: state,
            gpuActivity: gpuActivity,
            latestThroughput: latestThroughput
        )
        generatedAlerts.sort { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity.rawValue > rhs.severity.rawValue
            }
            return lhs.title < rhs.title
        }
        self.alerts = generatedAlerts
        self.health = Self.health(
            isRunning: isRunning,
            normalizedStatus: normalizedStatus,
            progressFraction: progress,
            alerts: generatedAlerts
        )
    }

    private static func health(
        isRunning: Bool,
        normalizedStatus: String,
        progressFraction: Double,
        alerts: [Alert]
    ) -> Health {
        if normalizedStatus == "failed" || normalizedStatus == "cancelled" {
            return .failed
        }
        if normalizedStatus == "succeeded" || normalizedStatus == "completed" || progressFraction >= 1 {
            return .complete
        }
        if alerts.contains(where: { $0.severity == .critical }) {
            return .stale
        }
        if alerts.contains(where: { $0.severity == .warning }) {
            return .attention
        }
        return isRunning ? .healthy : .idle
    }

    @MainActor
    private static func makeAlerts(
        isRunning: Bool,
        normalizedStatus: String,
        primaryIssue: String?,
        eventAge: TimeInterval?,
        artifactAge: TimeInterval?,
        artifactLoadAge: TimeInterval?,
        candidateAge: TimeInterval?,
        stalenessPolicy: StalenessPolicy,
        model: SimulationViewModel,
        state: LearningCampaignRunStoreState?,
        gpuActivity: LearningCampaignGPUActivitySnapshot,
        latestThroughput: Double?
    ) -> [Alert] {
        var alerts: [Alert] = []
        if let primaryIssue, !primaryIssue.isEmpty {
            alerts.append(Alert(
                id: "primary-issue",
                severity: normalizedStatus == "failed" ? .critical : .warning,
                title: "Primary issue",
                detail: primaryIssue
            ))
        }
        if isRunning {
            if let eventAge, eventAge >= stalenessPolicy.eventStream {
                alerts.append(Alert(
                    id: "event-stale",
                    severity: .critical,
                    title: "Runner event stream is stale",
                    detail: "No runner event has been received for \(ageText(eventAge))."
                ))
            } else if eventAge == nil {
                alerts.append(Alert(
                    id: "event-missing",
                    severity: .warning,
                    title: "Runner event stream has not reported yet",
                    detail: "The campaign is running, but no runner event has reached the UI."
                ))
            }
            if let artifactLoadAge,
               artifactLoadIsInFlight(model: model),
               artifactLoadAge >= stalenessPolicy.artifactLoad {
                alerts.append(Alert(
                    id: "artifact-loader-stalled",
                    severity: .critical,
                    title: "Artifact loader is stalled",
                    detail: "The current artifact load has not completed for \(ageText(artifactLoadAge))."
                ))
            }
            if let artifactAge, artifactAge >= stalenessPolicy.artifactChange {
                alerts.append(Alert(
                    id: "artifact-stale",
                    severity: .critical,
                    title: "Campaign artifacts are stale",
                    detail: "No artifact state change has been observed for \(ageText(artifactAge))."
                ))
            } else if artifactAge == nil {
                alerts.append(Alert(
                    id: "artifact-missing",
                    severity: .warning,
                    title: "Artifacts have not loaded yet",
                    detail: "The monitor is running, but no artifact snapshot has been applied."
                ))
            }
            if let candidateAge, candidateAge >= stalenessPolicy.candidate {
                alerts.append(Alert(
                    id: "candidate-stale",
                    severity: .warning,
                    title: "Candidate progress has stalled",
                    detail: "No candidate evaluation has completed for \(ageText(candidateAge))."
                ))
            }
            if latestThroughput == nil && (state?.liveCandidateEvaluationCount ?? 0) > 0 {
                alerts.append(Alert(
                    id: "throughput-missing",
                    severity: .warning,
                    title: "Throughput is unavailable",
                    detail: "Candidate events exist, but the latest event does not carry a usable throughput sample."
                ))
            }
        }
        if model.learningCampaignArtifactLoadFailureCount > 0 {
            alerts.append(Alert(
                id: "artifact-load-failures",
                severity: .warning,
                title: "Artifact loads have failed",
                detail: "\(model.learningCampaignArtifactLoadFailureCount) load failure(s) recorded in this UI session."
            ))
        }
        if gpuActivity.statusLabel == "ready" && isRunning && (state?.liveCandidateEvaluationCount ?? 0) > 0 {
            alerts.append(Alert(
                id: "gpu-ready-not-active",
                severity: .warning,
                title: "GPU evidence is not active",
                detail: "The accelerator is available, but recent candidate evidence does not show GPU-backed execution."
            ))
        }
        if let state,
           let passRate = state.bestTaskPassRate,
           passRate <= 0,
           state.completedGenerationCount > 0 {
            alerts.append(Alert(
                id: "pass-rate-zero",
                severity: .warning,
                title: "Task pass remains zero",
                detail: "At least one generation completed, but the best task pass rate is still 0%."
            ))
        }
        return alerts
    }

    @MainActor
    private static func artifactLoadIsInFlight(model: SimulationViewModel) -> Bool {
        guard let startedAt = model.learningCampaignLastArtifactLoadStartedAt else {
            return false
        }
        guard let finishedAt = model.learningCampaignLastArtifactLoadFinishedAt else {
            return true
        }
        return startedAt > finishedAt
    }

    private static func eventStreamStatus(
        isRunning: Bool,
        age: TimeInterval?,
        policy: StalenessPolicy
    ) -> String {
        guard isRunning else { return "idle" }
        guard let age else { return "pending" }
        if age >= policy.eventStream { return "stale" }
        if age >= policy.eventStream / 4 { return "quiet" }
        return "live"
    }

    private static func artifactLoadStatus(
        startedAt: Date?,
        finishedAt: Date?,
        failureCount: Int,
        now: Date,
        policy: StalenessPolicy
    ) -> String {
        if failureCount > 0 {
            return "warning"
        }
        guard let startedAt else { return "pending" }
        guard let finishedAt else {
            return now.timeIntervalSince(startedAt) >= policy.artifactLoad ? "stalled" : "loading"
        }
        if startedAt > finishedAt {
            return now.timeIntervalSince(startedAt) >= policy.artifactLoad ? "stalled" : "loading"
        }
        return "loaded"
    }

    private static func generationText(state: LearningCampaignRunStoreState?) -> String {
        guard let state else { return "--" }
        let planned = state.plannedGenerationCount
        if planned > 0 {
            return "\(state.completedGenerationCount)/\(planned)"
        }
        return "\(state.completedGenerationCount)"
    }

    private static func candidateText(completed: Int, planned: Int) -> String {
        guard planned > 0 else { return "\(completed)" }
        return "\(completed)/\(planned)"
    }

    private static func estimatedRemainingText(remainingCandidates: Int, throughput: Double?) -> String {
        guard remainingCandidates > 0 else { return "complete" }
        guard let throughput, throughput > 0 else { return "--" }
        return durationText(Double(remainingCandidates) / throughput)
    }

    private static func stalenessPolicy(
        state: LearningCampaignRunStoreState?,
        latestThroughput: Double?,
        hasLoadedArtifactState: Bool
    ) -> StalenessPolicy {
        let candidateCadence = latestThroughput.map { 1 / $0 }
            ?? state?.averageCandidateEvaluationDurationSeconds
            ?? (hasLoadedArtifactState ? 60 : 30)
        let parallelism = Double(max(1, state?.maxRequestedCandidateConcurrency ?? 1))
        let expectedBatchCadence = candidateCadence * max(1, min(parallelism, 16))
        let eventStream = boundedDuration(expectedBatchCadence * 4, lower: 30, upper: 600)
        let artifactChange = boundedDuration(eventStream * 2, lower: 60, upper: 1_200)
        let artifactLoad = boundedDuration(eventStream, lower: 15, upper: 180)
        let candidate = boundedDuration(expectedBatchCadence * 8, lower: 60, upper: 1_800)
        return StalenessPolicy(
            eventStream: eventStream,
            artifactChange: artifactChange,
            artifactLoad: artifactLoad,
            candidate: candidate
        )
    }

    private static func boundedDuration(
        _ value: TimeInterval,
        lower: TimeInterval,
        upper: TimeInterval
    ) -> TimeInterval {
        min(upper, max(lower, value))
    }

    private static func artifactRootLabel(
        state: LearningCampaignRunStoreState?,
        configuredPath: String
    ) -> String {
        if let state {
            return state.artifactDirectory.lastPathComponent
        }
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "--" }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    private static func gpuEvidenceLabel(activity: LearningCampaignGPUActivitySnapshot) -> String {
        let events = activity.gpuBackedEventFraction.map { formattedPercent($0) } ?? "--"
        let batches = activity.gpuBackedBatchFraction.map { formattedPercent($0) } ?? "--"
        return "\(activity.statusLabel) / events \(events) / batches \(batches)"
    }

    private static func throughputText(_ throughput: Double?) -> String {
        guard let throughput, throughput.isFinite, throughput > 0 else { return "--" }
        return String(format: "%.2f/s", throughput)
    }

    private static func ageText(_ age: TimeInterval?) -> String {
        guard let age else { return "--" }
        return durationText(age)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let bounded = max(0, seconds)
        if bounded < 60 {
            return String(format: "%.0fs", bounded)
        }
        if bounded < 3_600 {
            return "\(Int(bounded / 60))m \(Int(bounded.truncatingRemainder(dividingBy: 60)))s"
        }
        let hours = Int(bounded / 3_600)
        let minutes = Int((bounded.truncatingRemainder(dividingBy: 3_600)) / 60)
        return "\(hours)h \(minutes)m"
    }

    private static func formattedPercent(_ value: Double) -> String {
        String(format: "%.0f%%", min(1, max(0, value)) * 100)
    }

    private static func throughput(batch: LearningCampaignVectorizedBatchState) -> Double? {
        guard batch.elapsedSeconds > 0 else { return nil }
        return finitePositive(Double(batch.completedCandidateCount) / batch.elapsedSeconds)
    }

    private static func finitePositive(_ value: Double) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    private static let isoFormatStyle = Date.ISO8601FormatStyle()

    private static func parseISOTimestamp(_ value: String) -> Date? {
        do {
            return try isoFormatStyle.parse(value)
        } catch {
            return nil
        }
    }
}
