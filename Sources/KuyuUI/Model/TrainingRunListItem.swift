import Foundation
import KuyuTraining

/// One row in the training-run list: a point-in-time snapshot of a run
/// directory under the run root.
///
/// Unreadable directories carry the underlying reason instead of being
/// silently skipped, mirroring the registry contract.
public struct TrainingRunListItem: Identifiable, Sendable, Equatable {
    /// Run directory name (the run ID for readable runs).
    public let id: String
    public let createdAt: Date?
    public let task: String?
    public let profile: String?
    /// Liveness at snapshot time; nil when the run directory or its
    /// liveness inputs could not be read.
    public let liveness: TrainingRunLiveness?
    public let unreadableReason: String?

    public init(
        id: String,
        createdAt: Date?,
        task: String?,
        profile: String?,
        liveness: TrainingRunLiveness?,
        unreadableReason: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.task = task
        self.profile = profile
        self.liveness = liveness
        self.unreadableReason = unreadableReason
    }
}
