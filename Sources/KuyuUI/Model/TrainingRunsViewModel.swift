import Foundation
import KuyuTraining
import Observation

/// Observable client of the training-run contract archive: lists runs under
/// the run root, snapshots the selected run, and submits control commands
/// through the same file-based channel the CLI uses.
///
/// All file IO runs off the main actor in detached tasks; results land here
/// as immutable snapshots. Failures surface in `lastError` — never swallowed.
@Observable
@MainActor
public final class TrainingRunsViewModel {
    /// Pre-flight rejections for control commands that could never be
    /// applied by the run's writer process.
    public enum ControlSubmissionError: Error, Equatable, CustomStringConvertible {
        case noRunSelected
        case runAlreadyFinished(status: String)
        case writerProcessDead

        public var description: String {
            switch self {
            case .noRunSelected:
                return "No run selected."
            case .runAlreadyFinished(let status):
                return "Run already finished (\(status)); the command cannot be applied."
            case .writerProcessDead:
                return "The run's writer process is dead; the command would never be applied."
            }
        }
    }

    public private(set) var runRootPath: String?
    public private(set) var items: [TrainingRunListItem] = []
    public private(set) var detail: TrainingRunDetailSnapshot?
    public private(set) var lastError: String?
    /// Control sequence submitted from this UI and not yet acknowledged.
    public private(set) var pendingControlSequence: Int?
    public private(set) var lastRefreshedAt: Date?

    public var selectedRunID: String? {
        didSet {
            guard oldValue != selectedRunID else { return }
            detail = nil
            pendingControlSequence = nil
            Task { await self.refresh() }
        }
    }

    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    /// Polls the archive every 2 seconds until cancelled. Attach via `.task`
    /// so the poll stops when the workspace disappears.
    public func monitor() async {
        while !Task.isCancelled {
            await refresh()
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
        }
    }

    public func refresh() async {
        let selected = selectedRunID
        do {
            let runRoot = try TrainingRunContractSchema.resolveRunRoot(environment: environment)
            let snapshot = try await Task.detached(priority: .utility) {
                try Self.loadArchiveSnapshot(runRoot: runRoot, selectedRunID: selected)
            }.value
            runRootPath = runRoot.path
            // Selection may have moved while the snapshot was loading; do not
            // overwrite a newer selection's state with a stale one.
            guard selectedRunID == selected else { return }
            items = snapshot.items
            detail = snapshot.detail
            if let pending = pendingControlSequence,
               let control = snapshot.detail?.control,
               control.sequence >= pending,
               control.acknowledgment != nil {
                pendingControlSequence = nil
            }
            lastRefreshedAt = Date()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    public func submitControl(_ action: TrainingRunControlAction) async {
        guard let runRootPath, let selectedRunID else {
            lastError = ControlSubmissionError.noRunSelected.description
            return
        }
        let runDirectory = URL(fileURLWithPath: runRootPath, isDirectory: true)
            .appendingPathComponent(selectedRunID, isDirectory: true)
        do {
            let sequence = try await Task.detached(priority: .userInitiated) {
                try Self.submitControlCommand(action: action, runDirectory: runDirectory)
            }.value
            pendingControlSequence = sequence
            lastError = nil
            await refresh()
        } catch let error as ControlSubmissionError {
            lastError = error.description
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: - Archive IO (off-main)

    private struct ArchiveSnapshot: Sendable {
        let items: [TrainingRunListItem]
        let detail: TrainingRunDetailSnapshot?
    }

    private nonisolated static func loadArchiveSnapshot(
        runRoot: URL,
        selectedRunID: String?
    ) throws -> ArchiveSnapshot {
        let entries = try TrainingRunArchiveRegistry(runRoot: runRoot).list()
        var items: [TrainingRunListItem] = []
        items.reserveCapacity(entries.count)
        for entry in entries {
            let id = entry.directory.lastPathComponent
            switch entry.content {
            case .readable(let manifest):
                do {
                    let liveness = try TrainingRunArchiveReader(runDirectory: entry.directory).liveness()
                    items.append(TrainingRunListItem(
                        id: id,
                        createdAt: manifest.createdAt,
                        task: manifest.task,
                        liveness: liveness,
                        unreadableReason: nil
                    ))
                } catch {
                    items.append(TrainingRunListItem(
                        id: id,
                        createdAt: manifest.createdAt,
                        task: manifest.task,
                        liveness: nil,
                        unreadableReason: String(describing: error)
                    ))
                }
            case .unreadable(let reason):
                items.append(TrainingRunListItem(
                    id: id,
                    createdAt: nil,
                    task: nil,
                    liveness: nil,
                    unreadableReason: reason
                ))
            }
        }
        var detail: TrainingRunDetailSnapshot?
        if let selectedRunID,
           let entry = entries.first(where: { $0.directory.lastPathComponent == selectedRunID }),
           entry.manifest != nil {
            detail = try loadDetail(runDirectory: entry.directory)
        }
        return ArchiveSnapshot(items: items, detail: detail)
    }

    private nonisolated static func loadDetail(runDirectory: URL) throws -> TrainingRunDetailSnapshot {
        let reader = TrainingRunArchiveReader(runDirectory: runDirectory)
        let manifest = try reader.loadManifest()
        let liveness = try reader.liveness()
        let outcome = try reader.loadOutcome()
        let heartbeat = try reader.loadHeartbeat()
        let journal = try reader.readJournalValidatingEvaluationArtifacts()
        var control: TrainingRunDetailSnapshot.ControlStatus?
        if let sequence = try reader.latestControlSequence() {
            control = TrainingRunDetailSnapshot.ControlStatus(
                sequence: sequence,
                acknowledgment: try reader.controlAcknowledgment(sequence: sequence)
            )
        }
        return TrainingRunDetailSnapshot(
            runID: manifest.runID.rawValue,
            directoryPath: runDirectory.path,
            manifest: manifest,
            liveness: liveness,
            outcome: outcome,
            heartbeat: heartbeat,
            journalRecordCount: journal.records.count,
            journalTruncatedTailBytes: journal.truncatedTailBytes,
            lastRecord: journal.records.last,
            control: control
        )
    }

    private nonisolated static func submitControlCommand(
        action: TrainingRunControlAction,
        runDirectory: URL
    ) throws -> Int {
        let reader = TrainingRunArchiveReader(runDirectory: runDirectory)
        // Same operator-error guard as the CLI: a command to a run whose
        // writer can never apply it is rejected up front, not queued.
        switch try reader.liveness() {
        case .finished(let status):
            throw ControlSubmissionError.runAlreadyFinished(status: status.rawValue)
        case .interrupted:
            throw ControlSubmissionError.writerProcessDead
        case .paused(let processAlive) where !processAlive:
            throw ControlSubmissionError.writerProcessDead
        case .live, .paused:
            break
        }
        let sequence = ((try reader.latestControlSequence()) ?? 0) + 1
        try reader.submitControlCommand(TrainingRunControlCommand(
            sequence: sequence,
            action: action,
            requestedAt: Date(),
            requestedBy: "bounded-ui"
        ))
        return sequence
    }
}
