import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLX
import KuyuProfiles

@main
struct KuyuCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kuyu",
        abstract: "Kuyu training world command-line interface.",
        subcommands: [Run.self, Loop.self]
    )
}

enum TierChoice: String, CaseIterable, ExpressibleByArgument {
    case tier0
    case tier1
    case tier2
}

enum ControllerChoice: String, CaseIterable, ExpressibleByArgument {
    case baseline
    case manasMLX
}

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run a single KUY-ATT-1 suite.")

    @Option(help: "Controller to use: baseline or manasMLX.")
    var controller: ControllerChoice = .baseline

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Model descriptor path (optional).")
    var model: String = ""

    @Option(help: "kp gain for baseline controller.")
    var kp: Double = 2.0

    @Option(help: "kd gain for baseline controller.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @Flag(name: .customLong("no-aux"), help: "Disable aux prediction loss for MLX.")
    var noAux: Bool = false

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
    var noQualityGate: Bool = false

    @Option(name: .customLong("export-logs"), help: "Directory to export logs.")
    var exportLogsPath: String?

    @Option(name: .customLong("export-dataset"), help: "Directory to export training dataset.")
    var exportDatasetPath: String?

    @Flag(help: "Exit with non-zero code when the suite fails.")
    var failOnError: Bool = false

    @MainActor
    mutating func run() async throws {
        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let parameters = loadParameters(modelPath: model)
        let descriptor = loadDescriptor(modelPath: model)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )

        let output: KuyAtt1RunOutput
        switch controller {
        case .baseline:
            let runner = KuyAtt1Runner(
                parameters: parameters,
                schedule: schedule,
                determinism: determinism,
                noise: .zero,
                gains: gains
            )
            output = try await runner.runWithLogs()
        case .manasMLX:
            let request = SimulationRunRequest(
                controller: .manasMLX,
                gains: gains,
                cutPeriodSteps: cutPeriodSteps,
                noise: .zero,
                determinism: determinism,
                modelDescriptorPath: model,
                overrideParameters: model.isEmpty ? nil : parameters,
                useAux: !noAux,
                useQualityGating: !noQualityGate
            )
            let store = ManasMLXModelStore()
            output = try await store.runManasMLX(
                parameters: parameters,
                schedule: schedule,
                request: request,
                descriptor: descriptor,
                control: nil
            )
        }

        printSummary(output: output)

        if let exportLogsPath {
            let dir = URL(fileURLWithPath: exportLogsPath, isDirectory: true)
            _ = try KuyAtt1LogWriter().write(output: output, to: dir)
            print("[logs] exported to \(dir.path)")
        }

        if let exportDatasetPath {
            let dir = URL(fileURLWithPath: exportDatasetPath, isDirectory: true)
            let outputs = try TrainingDatasetExporter().write(output: output, to: dir)
            print("[dataset] exported \(outputs.count) scenarios to \(dir.path)")
        }

        if failOnError && !output.summary.suitePassed {
            throw ExitCode.failure
        }
    }
}

struct Loop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run a training loop with ManasMLX.")

    @Option(help: "Determinism tier: tier0, tier1, tier2.")
    var tier: TierChoice = .tier1

    @Option(name: .customLong("cut-period"), help: "CUT period in steps.")
    var cutPeriodSteps: UInt64 = 2

    @Option(help: "Model descriptor path (optional).")
    var model: String = ""

    @Option(help: "Iterations to run.")
    var iterations: Int = 10

    @Option(name: .customLong("sequence"), help: "Sequence length for MLX training.")
    var sequenceLength: Int = 16

    @Option(name: .customLong("epochs"), help: "Epochs per iteration.")
    var epochs: Int = 4

    @Option(name: .customLong("lr"), help: "Learning rate.")
    var learningRate: Double = 0.001

    @Flag(name: .customLong("no-aux"), help: "Disable aux prediction loss for MLX.")
    var noAux: Bool = false

    @Flag(name: .customLong("no-quality-gate"), help: "Disable quality gating for MLX.")
    var noQualityGate: Bool = false

    @Flag(name: .customLong("stop-on-pass"), help: "Stop the loop once the suite passes.")
    var stopOnPass: Bool = false

    @Option(name: .customLong("dataset-root"), help: "Dataset root directory (optional).")
    var datasetRootPath: String?

    @Option(help: "kp gain for baseline controller.")
    var kp: Double = 2.0

    @Option(help: "kd gain for baseline controller.")
    var kd: Double = 0.25

    @Option(name: .customLong("yaw-damping"), help: "Yaw damping gain for baseline controller.")
    var yawDamping: Double = 0.2

    @Option(name: .customLong("hover-scale"), help: "Hover thrust scale.")
    var hoverScale: Double = 1.0

    @MainActor
    mutating func run() async throws {
        let determinism = try makeDeterminism(tier: tier)
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
        let parameters = loadParameters(modelPath: model)
        let descriptor = loadDescriptor(modelPath: model)
        let gains = try ImuRateDampingCutGains(
            kp: kp,
            kd: kd,
            yawDamping: yawDamping,
            hoverThrustScale: hoverScale
        )

        let datasetRoot: URL
        if let datasetRootPath, !datasetRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            datasetRoot = URL(fileURLWithPath: datasetRootPath, isDirectory: true)
        } else {
            datasetRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-loop-\(UUID().uuidString)", isDirectory: true)
        }

        let request = SimulationRunRequest(
            controller: .manasMLX,
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            modelDescriptorPath: model,
            overrideParameters: model.isEmpty ? nil : parameters,
            useAux: !noAux,
            useQualityGating: !noQualityGate
        )

        let store = ManasMLXModelStore()
        let exporter = TrainingDatasetExporter()

        for iteration in 1...max(1, iterations) {
            print("[loop] iter=\(iteration) run started")
            let output = try await store.runManasMLX(
                parameters: parameters,
                schedule: schedule,
                request: request,
                descriptor: descriptor,
                control: nil
            )
            let score = score(from: output.summary)
            let overshoot = output.summary.aggregate.worstOvershootDegrees ?? -1
            let recovery = output.summary.aggregate.averageRecoveryTime ?? -1
            let hf = output.summary.aggregate.averageHfStabilityScore ?? -1
            print("[loop] iter=\(iteration) score=\(String(format: "%.3f", score)) overshoot=\(String(format: "%.2f", overshoot)) recovery=\(String(format: "%.2f", recovery)) hf=\(String(format: "%.2f", hf))")

            let iterDir = datasetRoot.appendingPathComponent("iter-\(iteration)", isDirectory: true)
            let outputs = try exporter.write(output: output, to: iterDir)
            print("[loop] iter=\(iteration) dataset exported count=\(outputs.count) path=\(iterDir.path)")

            let trainResult = try await store.trainCore(
                datasetURL: iterDir,
                sequenceLength: sequenceLength,
                learningRate: learningRate,
                epochs: epochs,
                useAux: !noAux,
                useQualityGating: !noQualityGate
            )
            print("[loop] iter=\(iteration) training loss=\(String(format: "%.6f", trainResult.finalLoss))")

            if stopOnPass && output.summary.suitePassed {
                print("[loop] pass achieved, stopping")
                return
            }
        }
    }
}

private func makeDeterminism(tier: TierChoice) throws -> DeterminismConfig {
    switch tier {
    case .tier0:
        return try DeterminismConfig(tier: .tier0)
    case .tier1:
        return try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
    case .tier2:
        return try DeterminismConfig(tier: .tier2)
    }
}

private func loadParameters(modelPath: String) -> ReferenceQuadrotorParameters {
    let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .baseline }
    do {
        let loader = RobotDescriptorLoader()
        let descriptor = try loader.loadDescriptor(path: trimmed)
        let inertial = try loader.loadPlantInertialProperties(descriptor: descriptor)
        return try ReferenceQuadrotorParameters.reference(
            from: inertial,
            robotID: descriptor.descriptor.robot.robotID
        )
    } catch {
        return .baseline
    }
}

private func loadDescriptor(modelPath: String) -> RobotDescriptor? {
    let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    do {
        let loader = RobotDescriptorLoader()
        let descriptor = try loader.loadDescriptor(path: trimmed)
        return descriptor.descriptor
    } catch {
        return nil
    }
}

private func score(from summary: ValidationSummary) -> Double {
    var score = summary.suitePassed ? 1.0 : 0.0
    if let worstOvershoot = summary.aggregate.worstOvershootDegrees {
        score -= min(1.0, worstOvershoot / 90.0) * 0.4
    }
    if let recovery = summary.aggregate.averageRecoveryTime {
        score -= min(1.0, recovery / 5.0) * 0.3
    }
    if let hf = summary.aggregate.averageHfStabilityScore {
        score += max(0.0, min(hf, 1.0)) * 0.2
    }
    return score
}

private func printSummary(output: KuyAtt1RunOutput) {
    let summary = output.summary
    let aggregate = summary.aggregate
    let overshoot = aggregate.worstOvershootDegrees.map { String(format: "%.2f", $0) } ?? "n/a"
    let recovery = aggregate.averageRecoveryTime.map { String(format: "%.2f", $0) } ?? "n/a"
    let hf = aggregate.averageHfStabilityScore.map { String(format: "%.2f", $0) } ?? "n/a"
    print("passed=\(summary.suitePassed) scenarios=\(summary.evaluations.count) overshoot=\(overshoot) recovery=\(recovery) hf=\(hf)")
}
