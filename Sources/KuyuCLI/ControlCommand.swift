import ArgumentParser
import Foundation
import KuyuTraining

enum ControlActionChoice: String, CaseIterable, ExpressibleByArgument {
    case pause
    case resume
    case stop

    var contractAction: TrainingRunControlAction {
        switch self {
        case .pause:
            return .pause
        case .resume:
            return .resume
        case .stop:
            return .stop
        }
    }
}

/// Sends a control command to a live training run through the contract's
/// file-based control channel. The trainer applies commands at iteration
/// boundaries only and acknowledges every command — including rejections.
struct Control: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "control",
        abstract: "Send pause/resume/stop to a training run."
    )

    @Argument(help: "Run ID (directory name under the run root).")
    var runID: String

    @Argument(help: "Action: pause, resume, or stop.")
    var action: ControlActionChoice

    @Option(name: .customLong("run-root"), help: "Run root directory. Defaults to KUYU_RUN_ROOT or ~/.kuyu/runs.")
    var runRootPath: String?

    @Flag(help: "Wait until the trainer acknowledges the command.")
    var wait: Bool = false

    @Option(help: "Seconds to wait for the acknowledgment with --wait.")
    var timeout: Double = 120

    mutating func run() async throws {
        guard timeout > 0 else {
            throw ValidationError("--timeout must be positive.")
        }
        let runRoot = try resolveTrainingRunRoot(override: runRootPath)
        let runDirectory = try resolveTrainingRunDirectory(runID: runID, runRoot: runRoot)
        let reader = TrainingRunArchiveReader(runDirectory: runDirectory)

        // A command to a run that can never apply it is operator error, not
        // a queued request — fail it up front with the actual run state.
        let liveness = try reader.liveness()
        switch liveness {
        case .finished(let status):
            throw ValidationError("Run \(runID) already finished (\(status.rawValue)); \(action.rawValue) cannot be applied.")
        case .interrupted:
            throw ValidationError("Run \(runID) is interrupted (writer process is dead); \(action.rawValue) would never be applied.")
        case .paused(let processAlive) where !processAlive:
            throw ValidationError("Run \(runID) is paused but its writer process is dead; \(action.rawValue) would never be applied.")
        case .live, .paused:
            break
        }

        let sequence = ((try reader.latestControlSequence()) ?? 0) + 1
        let command = TrainingRunControlCommand(
            sequence: sequence,
            action: action.contractAction,
            requestedAt: Date(),
            requestedBy: "kuyu-cli"
        )
        try reader.submitControlCommand(command)
        print("[control] submitted \(action.rawValue) sequence=\(sequence) run=\(runID)")

        guard wait else {
            return
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while clock.now < deadline {
            if let acknowledgment = try reader.controlAcknowledgment(sequence: sequence) {
                if acknowledgment.rejected {
                    let reason = acknowledgment.reason ?? "no reason recorded"
                    print("[control] rejected at iteration \(acknowledgment.iteration): \(reason)")
                    throw ExitCode.failure
                }
                print("[control] applied at iteration \(acknowledgment.iteration)")
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        print("[control] timed out after \(timeout)s waiting for acknowledgment of sequence \(sequence)")
        throw ExitCode.failure
    }
}
