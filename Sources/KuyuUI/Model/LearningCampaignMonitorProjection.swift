import Foundation
import KuyuMLXCampaignContracts
import KuyuTraining

struct LearningCampaignMonitorProjection: Sendable, Equatable {
    let persistedState: LearningCampaignRunStoreState?
    let isRunning: Bool
    let statusLabel: String
    let phase: String
    let latestEvent: String?
    let progressFraction: Double
    let artifactRoot: URL?
    let primaryIssue: String?

    init(
        execution: LearningCampaignExecutionSnapshot,
        persistedState: LearningCampaignRunStoreState?,
        configuredArtifactPath: String
    ) {
        let configuredRoot = Self.configuredRoot(configuredArtifactPath)
        let executionRoot = execution.terminalSummary?.artifactRoot ?? execution.artifactRoot
        let relevantState = Self.relevantState(
            persistedState,
            authoritativeRoot: executionRoot ?? configuredRoot
        )
        let boundedProgress = min(1, max(0, execution.progressFraction))

        self.persistedState = relevantState
        self.isRunning = execution.isRunning
        self.artifactRoot = executionRoot ?? relevantState?.artifactDirectory ?? configuredRoot

        if execution.isRunning {
            self.statusLabel = "running"
            self.phase = execution.phase
            self.latestEvent = execution.latestEvent
            self.progressFraction = min(0.999, boundedProgress)
            self.primaryIssue = execution.error
            return
        }

        if let summary = execution.terminalSummary {
            self.statusLabel = Self.statusLabel(summary: summary, executionPhase: execution.phase)
            self.phase = execution.phase
            self.latestEvent = execution.latestEvent
            self.progressFraction = boundedProgress
            self.primaryIssue = execution.error ?? Self.failureReason(summary.failureReasons)
            return
        }

        let normalizedPhase = execution.phase.lowercased()
        if Self.terminalPhases.contains(normalizedPhase) {
            self.statusLabel = normalizedPhase
            self.phase = execution.phase
            self.latestEvent = execution.latestEvent
            self.progressFraction = boundedProgress
            self.primaryIssue = execution.error
            return
        }

        self.statusLabel = relevantState?.statusLabel ?? "idle"
        self.phase = relevantState?.latestEvent?.phase ?? relevantState?.progress.lifecycleStage.rawValue ?? execution.phase
        self.latestEvent = relevantState?.latestEvent?.message ?? execution.latestEvent
        self.progressFraction = relevantState?.campaignProgressFraction ?? boundedProgress
        self.primaryIssue = relevantState?.primaryFailureReason ?? execution.error
    }

    private static let terminalPhases: Set<String> = [
        "completed",
        "failed",
        "rejected",
        "cancelled"
    ]

    private static func statusLabel(
        summary: TrainingRunSummary,
        executionPhase: String
    ) -> String {
        if summary.terminalState == .running {
            let normalizedPhase = executionPhase.lowercased()
            return terminalPhases.contains(normalizedPhase) ? normalizedPhase : "failed"
        }
        return summary.terminalState.rawValue
    }

    private static func failureReason(_ reasons: [String]) -> String? {
        guard !reasons.isEmpty else { return nil }
        return reasons.joined(separator: ", ")
    }

    private static func configuredRoot(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL
    }

    private static func relevantState(
        _ state: LearningCampaignRunStoreState?,
        authoritativeRoot: URL?
    ) -> LearningCampaignRunStoreState? {
        guard let state else { return nil }
        guard let authoritativeRoot else { return state }
        return sameLocation(state.artifactDirectory, authoritativeRoot) ? state : nil
    }

    static func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path
            == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
