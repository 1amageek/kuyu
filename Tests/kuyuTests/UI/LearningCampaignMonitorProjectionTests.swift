import Foundation
import KuyuMLXCampaignContracts
import KuyuTraining
@testable import KuyuUI
import Testing

@Suite("Learning campaign monitor projection")
struct LearningCampaignMonitorProjectionTests {
    @Test(.timeLimit(.minutes(1)))
    func activeExecutionRejectsCompletedStateFromAnotherArtifactRoot() {
        let previousRoot = URL(fileURLWithPath: "/tmp/kuyu-previous", isDirectory: true)
        let activeRoot = URL(fileURLWithPath: "/tmp/kuyu-active", isDirectory: true)
        let projection = LearningCampaignMonitorProjection(
            execution: executionSnapshot(
                runID: "active",
                artifactRoot: activeRoot,
                isRunning: true,
                progressFraction: 0.25,
                phase: "candidate"
            ),
            persistedState: runState(
                artifactRoot: previousRoot,
                status: "completed"
            ),
            configuredArtifactPath: previousRoot.path
        )

        #expect(projection.persistedState == nil)
        #expect(projection.statusLabel == "running")
        #expect(projection.phase == "candidate")
        #expect(projection.progressFraction == 0.25)
        #expect(projection.artifactRoot == activeRoot)
    }

    @Test(.timeLimit(.minutes(1)))
    func failedTerminalSummaryOverridesLaggingPersistedStatus() {
        let root = URL(fileURLWithPath: "/tmp/kuyu-failed", isDirectory: true)
        let summary = TrainingRunSummary(
            runID: TrainingRunID("failed"),
            artifactRoot: root,
            terminalState: .failed,
            generationCount: 2,
            candidateCount: 8,
            failureReasons: ["worker exited"]
        )
        let projection = LearningCampaignMonitorProjection(
            execution: executionSnapshot(
                runID: "failed",
                artifactRoot: root,
                progressFraction: 0.4,
                phase: "failed",
                latestEvent: "Campaign failed",
                error: "worker exited",
                terminalSummary: summary
            ),
            persistedState: runState(artifactRoot: root, status: "running"),
            configuredArtifactPath: root.path
        )

        #expect(projection.persistedState != nil)
        #expect(projection.statusLabel == "failed")
        #expect(projection.progressFraction == 0.4)
        #expect(projection.primaryIssue == "worker exited")
    }

    private func executionSnapshot(
        runID: String,
        artifactRoot: URL,
        isRunning: Bool = false,
        progressFraction: Double,
        phase: String,
        latestEvent: String? = nil,
        error: String? = nil,
        terminalSummary: TrainingRunSummary? = nil
    ) -> LearningCampaignExecutionSnapshot {
        LearningCampaignExecutionSnapshot(
            runID: TrainingRunID(runID),
            artifactRoot: artifactRoot,
            isRunning: isRunning,
            progressFraction: progressFraction,
            phase: phase,
            latestEvent: latestEvent,
            error: error,
            terminalSummary: terminalSummary
        )
    }

    private func runState(
        artifactRoot: URL,
        status: String
    ) -> LearningCampaignRunStoreState {
        LearningCampaignRunStoreState(
            artifactDirectory: artifactRoot,
            plan: nil,
            status: LearningCampaignStatus(
                status: status,
                exitCode: 0,
                startedAt: "2026-07-15T00:00:00Z",
                finishedAt: "2026-07-15T00:01:00Z"
            ),
            summary: nil,
            validation: nil,
            retention: nil,
            accelerator: nil,
            progressEvents: [],
            generations: [],
            candidates: [],
            vectorizedBatches: [],
            acceptedCheckpoints: []
        )
    }
}
