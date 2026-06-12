import Foundation
import KuyuTraining

/// Point-in-time snapshot of one run directory, read entirely from the run
/// contract files (manifest, outcome, heartbeat, journal, control channel).
public struct TrainingRunDetailSnapshot: Sendable {
    /// Latest control command sequence and its acknowledgment, if any.
    public struct ControlStatus: Sendable, Equatable {
        public let sequence: Int
        /// nil while the trainer has not yet reached an iteration boundary.
        public let acknowledgment: TrainingRunControlAcknowledgment?

        public init(sequence: Int, acknowledgment: TrainingRunControlAcknowledgment?) {
            self.sequence = sequence
            self.acknowledgment = acknowledgment
        }
    }

    public let runID: String
    public let directoryPath: String
    public let manifest: TrainingRunManifest
    public let liveness: TrainingRunLiveness
    public let outcome: TrainingRunOutcome
    public let heartbeat: TrainingRunHeartbeat?
    public let journalRecordCount: Int
    public let journalTruncatedTailBytes: Int
    public let lastRecord: TrainingRunIterationRecord?
    public let control: ControlStatus?

    public init(
        runID: String,
        directoryPath: String,
        manifest: TrainingRunManifest,
        liveness: TrainingRunLiveness,
        outcome: TrainingRunOutcome,
        heartbeat: TrainingRunHeartbeat?,
        journalRecordCount: Int,
        journalTruncatedTailBytes: Int,
        lastRecord: TrainingRunIterationRecord?,
        control: ControlStatus?
    ) {
        self.runID = runID
        self.directoryPath = directoryPath
        self.manifest = manifest
        self.liveness = liveness
        self.outcome = outcome
        self.heartbeat = heartbeat
        self.journalRecordCount = journalRecordCount
        self.journalTruncatedTailBytes = journalTruncatedTailBytes
        self.lastRecord = lastRecord
        self.control = control
    }
}
