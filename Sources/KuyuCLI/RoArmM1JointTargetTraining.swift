import ArgumentParser
import Foundation
import KuyuCore
import KuyuPhysics
import KuyuTraining

struct TrainRoArmM1JointTargets: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "train-roarm-m1-joint-targets",
        abstract: "Run the RoArm M1 camera-free joint target tracking smoke training artifact."
    )

    @Option(help: "RoArm M1 robot manifest path.")
    var model: String = "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json"

    @Option(help: "Output directory for the training report and dataset.")
    var output: String = "/tmp/kuyu-roarm-m1-joint-target-training"

    @Option(help: "Simulation duration in seconds.")
    var duration: Double = 2.0

    @Option(help: "Deterministic scenario seed.")
    var seed: UInt64 = 7

    @Flag(name: .customLong("no-hindsight"), help: "Disable achieved-goal relabel records.")
    var noHindsight: Bool = false

    func run() async throws {
        let loaded = try KuyuModelLoader().loadRobot(path: model)
        guard loaded.manifest.robotID == RoArmM1JointTargetTrainingGoal.canonical.robotManifestID else {
            throw ValidationError("Expected roarm-m1-v0 robot manifest, got \(loaded.manifest.robotID).")
        }
        guard duration.isFinite, duration > 0 else {
            throw ValidationError("--duration must be a positive finite number.")
        }

        let request = ArticulatedRigidBodySimulationRequest(
            body: loaded.body,
            world: loaded.world,
            embodiment: loaded.embodiment,
            compatibilityReport: loaded.compatibilityReport,
            determinism: .tier0Strict,
            readinessLevel: RoArmM1JointTargetTrainingGoal.canonical.requiredReadinessLevel,
            duration: duration,
            timeStep: try TimeStep(delta: loaded.world.time.fixedStepSeconds),
            seed: ScenarioSeed(seed)
        )
        let log = try await ArticulatedRigidBodySimulator().run(request: request)
        let builder = RoArmM1JointTargetTrainingDatasetBuilder(
            config: RoArmM1JointTargetTrainingDatasetBuilderConfig(
                includeHindsightRelabels: !noHindsight
            )
        )
        let result = try builder.build(from: log)
        let outputURL = URL(fileURLWithPath: output, isDirectory: true)
        try builder.write(result: result, to: outputURL)

        print("[roarm-m1-training] goal=\(result.report.goal.goalID)")
        print("[roarm-m1-training] status=\(result.report.status.rawValue)")
        print("[roarm-m1-training] records=\(result.report.recordCount) source=\(result.report.sourceRecordCount) hindsight=\(result.report.hindsightRecordCount)")
        print("[roarm-m1-training] meanAbsErrorRad=\(format(result.report.meanAbsoluteErrorRadians)) maxAbsErrorRad=\(format(result.report.maximumAbsoluteErrorRadians))")
        print("[roarm-m1-training] movementRad=\(format(result.report.movementMagnitudeRadians)) limitViolations=\(result.report.jointLimitViolationCount)")
        print("[roarm-m1-training] output=\(outputURL.path)")

        guard result.report.passed else {
            throw ExitCode.failure
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
