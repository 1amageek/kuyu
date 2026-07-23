import Foundation
import KuyuMLX
import KuyuMLXTrainingRuntime
import KuyuTraining

public struct ManasMLXTrainingWorkerService: Sendable {
    public enum WorkerError: Error, Sendable, Equatable {
        case missingProjectRootAuthorization(String)
        case executionAndLeaseReleaseFailed(execution: String, release: String)
        case terminalFailurePersistenceFailed(primary: String, persistence: String)
    }

    public typealias EventHandler = @Sendable (TrainingRunEvent) async -> Void

    private let executor: any AnyTrainingRunExecuting

    public init(
        executor: any AnyTrainingRunExecuting = ManasMLXTrainingRunExecutor()
    ) {
        self.executor = executor
    }

    public func execute(
        _ invocation: ManasMLXTrainingWorkerInvocation
    ) async throws -> ManasMLXTrainingWorkerOutcome {
        try await execute(invocation) { _ in }
    }

    public func execute(
        _ invocation: ManasMLXTrainingWorkerInvocation,
        onEvent: @escaping EventHandler
    ) async throws -> ManasMLXTrainingWorkerOutcome {
        let store = TrainingRunWorkerLaunchArtifactStore(
            rootDirectory: invocation.launchRoot
        )
        let artifact = try store.validatedArtifact(
            launchID: invocation.launchID,
            expectedSHA256Digest: invocation.launchDigest
        )
        if artifactProjectRoot(artifact) != nil,
           invocation.allowedProjectRoots.isEmpty {
            throw WorkerError.missingProjectRootAuthorization(
                artifact.operation.runID.rawValue
            )
        }
        try TrainingRunWorkerPathAuthorizationPolicy(
            allowedArtifactRoots: invocation.allowedArtifactRoots,
            allowedSourceRoots: invocation.allowedSourceRoots,
            allowedProjectRoots: invocation.allowedProjectRoots
        ).validate(artifact)

        let stopRequest = TrainingRunWorkerStopRequest(
            artifactRoot: artifact.operation.artifactRoot,
            launchID: artifact.launchID,
            attemptID: artifact.attemptID
        )
        let lease = try TrainingRunWorkerLease(
            ownershipRootDirectory: invocation.launchRoot.appendingPathComponent(
                TrainingRunWorkerLease.ownershipDirectoryName,
                isDirectory: true
            ),
            launchID: invocation.launchID,
            runID: artifact.operation.runID,
            artifactRoot: artifact.operation.artifactRoot,
            launchSHA256Digest: invocation.launchDigest,
            attemptID: artifact.attemptID
        )
        var terminalSummary: TrainingRunSummary?
        do {
            let progressRecorder = try TrainingRunWorkerProgressRecorder(
                progressRoot: store.launchDirectory(for: invocation.launchID),
                workerAttemptIdentity: lease.metadata.attemptIdentity
            )
            try TrainingRunWorkerSourceIntegrityVerifier(
                allowedSourceRoots: invocation.allowedSourceRoots
            ).verify(artifact)
            let executionArtifact = try TrainingRunWorkerSourceSnapshotStore()
                .durableArtifact(artifact)
            let executionSourceRoots = invocation.allowedSourceRoots
                + [executionArtifact.operation.artifactRoot]
            try TrainingRunWorkerPathAuthorizationPolicy(
                allowedArtifactRoots: invocation.allowedArtifactRoots,
                allowedSourceRoots: executionSourceRoots,
                allowedProjectRoots: invocation.allowedProjectRoots
            ).validate(executionArtifact)
            try TrainingRunWorkerSourceIntegrityVerifier(
                allowedSourceRoots: executionSourceRoots
            ).verify(executionArtifact)
            let summary = try await TrainingRunWorkerExecutionService(
                executor: executor
            ).execute(
                executionArtifact,
                workerAttemptIdentity: lease.metadata.attemptIdentity,
                stopRequest: stopRequest,
                onEvent: { event in
                    if case .progress(let progress) = event {
                        try await progressRecorder.record(progress)
                    }
                    await onEvent(event)
                }
            )
            terminalSummary = summary
            try await lease.release()
            return outcome(from: summary)
        } catch {
            let primaryError = error
            let primaryFailure = String(describing: primaryError)
            var persistenceFailure: String?
            if terminalSummary != nil || !(primaryError is CancellationError) {
                do {
                    try persistFailure(
                        primaryFailure,
                        artifact: artifact,
                        workerAttemptIdentity: lease.metadata.attemptIdentity,
                        preserving: terminalSummary
                    )
                } catch {
                    persistenceFailure = String(describing: error)
                }
            }
            do {
                try await lease.release()
            } catch {
                let releaseFailure = String(describing: error)
                do {
                    try persistFailure(
                        "\(primaryFailure); lease release failed: \(releaseFailure)",
                        artifact: artifact,
                        workerAttemptIdentity: lease.metadata.attemptIdentity,
                        preserving: terminalSummary
                    )
                } catch {
                    throw WorkerError.terminalFailurePersistenceFailed(
                        primary: "\(primaryFailure); lease release failed: \(releaseFailure)",
                        persistence: String(describing: error)
                    )
                }
                throw WorkerError.executionAndLeaseReleaseFailed(
                    execution: primaryFailure,
                    release: releaseFailure
                )
            }
            if let persistenceFailure {
                throw WorkerError.terminalFailurePersistenceFailed(
                    primary: primaryFailure,
                    persistence: persistenceFailure
                )
            }
            if primaryError is CancellationError {
                let outcomeArtifact = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
                    in: artifact.operation.artifactRoot,
                    expectedRunID: artifact.operation.runID,
                    expectedWorkerAttemptIdentity: lease.metadata.attemptIdentity
                )
                return outcome(from: outcomeArtifact.summary)
            }
            throw primaryError
        }
    }

    private func artifactProjectRoot(
        _ artifact: TrainingRunWorkerLaunchArtifact
    ) -> URL? {
        switch artifact.operation {
        case .start(let request):
            request.projectRoot
        case .resume(let request):
            request.projectRoot
        }
    }

    private func outcome(
        from summary: TrainingRunSummary
    ) -> ManasMLXTrainingWorkerOutcome {
        return ManasMLXTrainingWorkerOutcome(
            runID: summary.runID.rawValue,
            artifactRoot: summary.artifactRoot,
            terminalState: summary.terminalState,
            generationCount: summary.generationCount,
            candidateCount: summary.candidateCount,
            hasAcceptedCheckpoint: summary.acceptedCheckpoint != nil,
            failureReasons: summary.failureReasons
        )
    }

    private func persistFailure(
        _ reason: String,
        artifact: TrainingRunWorkerLaunchArtifact,
        workerAttemptIdentity: TrainingRunWorkerAttemptIdentity,
        preserving summary: TrainingRunSummary?
    ) throws {
        let failureSummary = TrainingRunSummary(
            runID: artifact.operation.runID,
            artifactRoot: artifact.operation.artifactRoot,
            terminalState: .failed,
            generationCount: summary?.generationCount ?? 0,
            candidateCount: summary?.candidateCount ?? 0,
            failureReasons: (summary?.failureReasons ?? []) + [reason]
        )
        _ = try TrainingRunSummaryOutcomeArtifactStore().write(
            summary: failureSummary,
            expectedRunID: artifact.operation.runID,
            workerAttemptIdentity: workerAttemptIdentity,
            to: artifact.operation.artifactRoot
        )
    }

}
