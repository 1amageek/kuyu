import ArgumentParser
import Foundation
import KuyuTraining

/// Resolves the run root from an explicit CLI override, falling back to
/// `KUYU_RUN_ROOT` and the durable default (`~/.kuyu/runs`).
func resolveTrainingRunRoot(override: String?) throws -> URL {
    if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    return try TrainingRunContractSchema.resolveRunRoot()
}

/// Resolves an existing run directory by run ID; missing runs are a typed
/// CLI validation error, never an empty result.
func resolveTrainingRunDirectory(runID: String, runRoot: URL) throws -> URL {
    let directory = runRoot.appendingPathComponent(runID, isDirectory: true)
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
    guard exists, isDirectory.boolValue else {
        throw ValidationError("Run \(runID) not found under \(runRoot.path).")
    }
    return directory
}

func describeTrainingRunLiveness(_ liveness: TrainingRunLiveness) -> String {
    switch liveness {
    case .live(let processIdentifier):
        return "live (pid \(processIdentifier))"
    case .finished(let status):
        return status.rawValue
    case .paused(let processAlive):
        return processAlive ? "paused" : "paused (writer dead)"
    case .interrupted:
        return "interrupted"
    }
}

/// Run inspection commands operating purely on the training-run contract —
/// the same files every other client (UI, tests) reads.
struct Runs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runs",
        abstract: "Inspect training runs under the run root.",
        subcommands: [List.self, Show.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List training runs, newest first."
        )

        @Option(name: .customLong("run-root"), help: "Run root directory. Defaults to KUYU_RUN_ROOT or ~/.kuyu/runs.")
        var runRootPath: String?

        mutating func run() async throws {
            let runRoot = try resolveTrainingRunRoot(override: runRootPath)
            let entries = try TrainingRunArchiveRegistry(runRoot: runRoot).list()
            guard !entries.isEmpty else {
                print("No runs under \(runRoot.path).")
                return
            }
            let dateFormatter = ISO8601DateFormatter()
            print("RUN ID                                            STATUS                CREATED               TASK")
            for entry in entries {
                let runID = entry.directory.lastPathComponent
                switch entry.content {
                case .readable(let manifest):
                    let status: String
                    do {
                        let liveness = try TrainingRunArchiveReader(runDirectory: entry.directory).liveness()
                        status = describeTrainingRunLiveness(liveness)
                    } catch {
                        status = "error: \(error)"
                    }
                    let created = dateFormatter.string(from: manifest.createdAt)
                    print("\(runID.padding(toLength: 49, withPad: " ", startingAt: 0)) \(status.padding(toLength: 21, withPad: " ", startingAt: 0)) \(created)  \(manifest.task)")
                case .unreadable(let reason):
                    print("\(runID.padding(toLength: 49, withPad: " ", startingAt: 0)) unreadable: \(reason)")
                }
            }
        }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show manifest, liveness, journal, and control state for one run."
        )

        @Argument(help: "Run ID (directory name under the run root).")
        var runID: String

        @Option(name: .customLong("run-root"), help: "Run root directory. Defaults to KUYU_RUN_ROOT or ~/.kuyu/runs.")
        var runRootPath: String?

        mutating func run() async throws {
            let runRoot = try resolveTrainingRunRoot(override: runRootPath)
            let runDirectory = try resolveTrainingRunDirectory(runID: runID, runRoot: runRoot)
            let reader = TrainingRunArchiveReader(runDirectory: runDirectory)
            let dateFormatter = ISO8601DateFormatter()

            let manifest = try reader.loadManifest()
            print("Run:         \(manifest.runID.rawValue)")
            print("Directory:   \(runDirectory.path)")
            print("Created:     \(dateFormatter.string(from: manifest.createdAt))")
            print("Task:        \(manifest.task)  profile=\(manifest.profile)  version=\(manifest.semanticVersion)")
            print("Code:        \(manifest.code.gitHead)\(manifest.code.gitDirty ? " (dirty)" : "") [\(manifest.code.buildConfiguration)]")
            let salt = manifest.determinism.noiseSeedSalt.map(String.init) ?? "none"
            print("Determinism: tier=\(manifest.determinism.tier) mlxSeed=\(manifest.determinism.mlxGlobalSeed) noiseSalt=\(salt)")
            print("Host:        \(manifest.host.hostName) pid=\(manifest.host.processIdentifier)")

            let liveness = try reader.liveness()
            print("Status:      \(describeTrainingRunLiveness(liveness))")

            let outcome = try reader.loadOutcome()
            var outcomeLine = "Outcome:     status=\(outcome.status.rawValue) updated=\(dateFormatter.string(from: outcome.updatedAt))"
            if let finalIteration = outcome.finalIteration {
                outcomeLine += " finalIteration=\(finalIteration)"
            }
            if let failureReason = outcome.failureReason {
                outcomeLine += " failureReason=\(failureReason)"
            }
            if let acceptedCheckpointPath = outcome.acceptedCheckpointPath {
                outcomeLine += " acceptedCheckpoint=\(acceptedCheckpointPath)"
            }
            print(outcomeLine)

            if let heartbeat = try reader.loadHeartbeat() {
                print("Heartbeat:   iter=\(heartbeat.iteration) phase=\(heartbeat.phase) at=\(dateFormatter.string(from: heartbeat.updatedAt)) pid=\(heartbeat.processIdentifier)")
            } else {
                print("Heartbeat:   none")
            }

            let journal = try reader.readJournal()
            var journalLine = "Journal:     \(journal.records.count) records"
            if journal.truncatedTailBytes > 0 {
                journalLine += " (torn tail: \(journal.truncatedTailBytes) bytes)"
            }
            print(journalLine)
            if let last = journal.records.last {
                let metrics = (last.evaluation?.metrics ?? [:])
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\(String(format: "%.4f", $0.value))" }
                    .joined(separator: " ")
                print("Last record: iteration=\(last.iteration) \(metrics)")
                if let checkpoint = last.checkpoint {
                    print("Checkpoint:  \(checkpoint.path) sha256=\(checkpoint.sha256Digest)")
                }
            }

            if let sequence = try reader.latestControlSequence() {
                if let acknowledgment = try reader.controlAcknowledgment(sequence: sequence) {
                    var controlLine = "Control:     sequence=\(sequence) command=\(acknowledgment.command) \(acknowledgment.rejected ? "rejected" : "applied") at iteration \(acknowledgment.iteration)"
                    if let reason = acknowledgment.reason {
                        controlLine += " (\(reason))"
                    }
                    print(controlLine)
                } else {
                    print("Control:     sequence=\(sequence) pending (not yet acknowledged)")
                }
            } else {
                print("Control:     no commands submitted")
            }
        }
    }
}
