import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLX
import KuyuPhysics
import KuyuTraining

struct TrainRoArmM1JointTargets: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "train-roarm-m1-arm-gripper",
        abstract: "Run RoArm M1 camera-free arm and gripper smoke training and write a Manas bundle."
    )

    @Option(help: "RoArm M1 robot manifest path.")
    var model: String = "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json"

    @Option(help: "Output directory for the training report and dataset.")
    var output: String = "/tmp/kuyu-roarm-m1-arm-gripper-training"

    @Option(name: .customLong("checkpoint-output"), help: "Output .manasbundle directory for the trained Manas model.")
    var checkpointOutput: String?

    @Option(help: "Simulation duration in seconds.")
    var duration: Double = 2.0

    @Option(help: "Deterministic scenario seed.")
    var seed: UInt64 = 7

    @Flag(name: .customLong("no-hindsight"), help: "Disable achieved-goal relabel records.")
    var noHindsight: Bool = false

    @Option(name: .customLong("manas-sequence"), help: "Sequence length for ManasMLX smoke training.")
    var manasSequenceLength: Int = 8

    @Option(name: .customLong("manas-epochs"), help: "Epoch count for ManasMLX smoke training.")
    var manasEpochs: Int = 8

    @Option(name: .customLong("manas-lr"), help: "Learning rate for ManasMLX smoke training.")
    var manasLearningRate: Double = 0.001

    @Option(name: .customLong("manas-max-batches"), help: "Maximum ManasMLX training batches.")
    var manasMaxBatches: Int = 16

    @Flag(name: .customLong("skip-manas"), help: "Only write the Kuyu dataset and report without training a Manas bundle.")
    var skipManas: Bool = false

    @MainActor
    func run() async throws {
        let loaded = try KuyuModelLoader().loadRobot(path: model)
        guard loaded.manifest.robotID == RoArmM1JointTargetTrainingGoal.canonical.robotManifestID else {
            throw ValidationError("Expected roarm-m1-v0 robot manifest, got \(loaded.manifest.robotID).")
        }
        guard duration.isFinite, duration > 0 else {
            throw ValidationError("--duration must be a positive finite number.")
        }
        if !skipManas {
            guard manasSequenceLength > 0 else {
                throw ValidationError("--manas-sequence must be greater than 0.")
            }
            guard manasEpochs > 0 else {
                throw ValidationError("--manas-epochs must be greater than 0.")
            }
            guard manasLearningRate.isFinite, manasLearningRate > 0 else {
                throw ValidationError("--manas-lr must be a positive finite number.")
            }
            guard manasMaxBatches > 0 else {
                throw ValidationError("--manas-max-batches must be greater than 0.")
            }
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

        guard !skipManas else {
            print("[roarm-m1-training] manas=skipped")
            return
        }

        let checkpointURL = URL(
            fileURLWithPath: checkpointOutput ?? outputURL
                .appendingPathComponent("manas", isDirectory: true)
                .appendingPathComponent("roarm-m1-arm-gripper.manasbundle", isDirectory: true)
                .path,
            isDirectory: true
        )
        let manasResult = try await RoArmM1ArmGripperManasTrainer().train(
            request: RoArmM1ArmGripperManasTrainingRequest(
                datasetURL: outputURL.appendingPathComponent("dataset", isDirectory: true),
                checkpointURL: checkpointURL,
                embodiment: loaded.embodiment,
                sequenceLength: manasSequenceLength,
                epochs: manasEpochs,
                learningRate: manasLearningRate,
                maxBatches: manasMaxBatches,
                useQualityGating: false,
                closedLoopSimulationRequest: request,
                useClosedLoopSineTarget: true
            )
        )

        print("[roarm-m1-training] manasCheckpoint=\(manasResult.checkpointURL.path)")
        print("[roarm-m1-training] manasBundle=\(manasResult.bundleManifest.bundleID)")
        print("[roarm-m1-training] manasRuntime observation=\(manasResult.bundleManifest.runtimeContract.observationSchemaID) drives=\(manasResult.bundleManifest.runtimeContract.driveSemanticsID)")
        print("[roarm-m1-training] manasFinalLoss=\(format(manasResult.training.finalLoss)) epochs=\(manasResult.training.epochs)")
        print("[roarm-m1-training] manasOpenLoopMAE=\(formatOptional(manasResult.training.openLoopDriveMAE)) reloadedOpenLoopMAE=\(formatOptional(manasResult.reloadedOpenLoopFit?.meanAbsoluteError))")
        if let closedLoop = manasResult.closedLoopEvaluation {
            print("[roarm-m1-training] manasClosedLoop passed=\(closedLoop.passed) meanAbsErrorRad=\(format(closedLoop.meanAbsoluteErrorRadians)) maxAbsErrorRad=\(format(closedLoop.maximumAbsoluteErrorRadians)) movementRad=\(format(closedLoop.movementMagnitudeRadians)) limitViolations=\(closedLoop.jointLimitViolationCount)")
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private func formatOptional(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return format(value)
    }
}
