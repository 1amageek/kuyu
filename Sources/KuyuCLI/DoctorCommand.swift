import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXCore
import KuyuTraining
import Metal

/// Environment diagnostics for the Kuyu toolchain. Checks the Metal GPU,
/// the MLX runtime (metallib + optional robot manifest / checkpoint), and
/// the training run root, reporting each as PASS or FAIL. Exits non-zero
/// when any check fails so it can gate scripts and CI.
struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose the local environment: Metal GPU, MLX runtime, and training run root."
    )

    @Option(help: "Robot manifest path to validate (optional).")
    var model: String = ""

    @Option(help: "Checkpoint directory to validate (optional; loads safetensors via MLX).")
    var checkpoint: String = ""

    mutating func run() throws {
        var failures = 0
        var checkIndex = 0
        let checkCount = 3
        func check(_ name: String) { checkIndex += 1; print("[doctor \(checkIndex)/\(checkCount)] \(name)") }
        func pass(_ detail: String) { print("[doctor]   PASS — \(detail)") }
        func fail(_ detail: String) { failures += 1; print("[doctor]   FAIL — \(detail)") }
        func info(_ detail: String) { print("[doctor]   \(detail)") }

        // Check 1: Metal GPU device.
        check("Metal GPU device")
        if let device = MTLCreateSystemDefaultDevice() {
            let workingSetGiB = Double(device.recommendedMaxWorkingSetSize) / (1024 * 1024 * 1024)
            pass("\(device.name) (recommended working set \(String(format: "%.1f", workingSetGiB)) GiB)")
        } else {
            fail("no Metal device available — MLX training and inference cannot run on this machine")
        }

        // Check 2: MLX runtime, plus optional robot manifest and checkpoint validation.
        check("MLX runtime preflight")
        do {
            let checkpointURL: URL?
            let trimmedCheckpoint = checkpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedCheckpoint.isEmpty {
                checkpointURL = nil
            } else {
                checkpointURL = URL(fileURLWithPath: trimmedCheckpoint, isDirectory: true)
            }
            let report = try ManasMLXE2EPreflight().check(
                robotManifestPath: model,
                sourceCheckpointURL: checkpointURL
            )
            if report.robotManifestLoaded, let path = report.robotManifestPath {
                info("robot manifest loaded: \(path)")
            }
            if report.sourceCheckpointLoadable, let url = report.sourceCheckpointURL {
                info("checkpoint loadable: \(url.path)")
            }
            pass("MLX runtime ready")
        } catch {
            fail("\(error)")
        }

        // Check 3: training run root resolution and writability.
        check("Training run root")
        do {
            let environment = ProcessInfo.processInfo.environment
            let runRoot = try TrainingRunContractSchema.resolveRunRoot(environment: environment)
            if let override = environment[TrainingRunContractSchema.runRootEnvironmentKey] {
                info("\(TrainingRunContractSchema.runRootEnvironmentKey)=\(override)")
            } else {
                info("\(TrainingRunContractSchema.runRootEnvironmentKey) not set; using default")
            }
            try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
            let probeURL = runRoot.appendingPathComponent(".kuyu-doctor-probe-\(UUID().uuidString)")
            try Data("probe".utf8).write(to: probeURL, options: [.atomic])
            try FileManager.default.removeItem(at: probeURL)
            pass("writable: \(runRoot.path)")
        } catch {
            fail("\(error)")
        }

        print("")
        if failures == 0 {
            print("[doctor] ALL CHECKS PASSED")
        } else {
            print("[doctor] \(failures) CHECK(S) FAILED")
            throw ExitCode.failure
        }
    }
}
