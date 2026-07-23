import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXRoArmM1

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
        let outputURL = URL(fileURLWithPath: output, isDirectory: true)
        let checkpointURL = URL(
            fileURLWithPath: checkpointOutput ?? outputURL
                .appendingPathComponent("manas", isDirectory: true)
                .appendingPathComponent("roarm-m1-arm-gripper.manasbundle", isDirectory: true)
                .path,
            isDirectory: true
        )
        let manasTraining = skipManas ? nil : RoArmM1ArmGripperTrainingPipelineService.ManasTrainingConfig(
            checkpointURL: checkpointURL,
            sequenceLength: manasSequenceLength,
            epochs: manasEpochs,
            learningRate: manasLearningRate,
            maxBatches: manasMaxBatches
        )
        let manasTrainingOperation: RoArmM1ArmGripperTrainingPipelineService.ManasTrainingOperation?
        if skipManas {
            manasTrainingOperation = nil
        } else {
            manasTrainingOperation = { request in
                try await RoArmM1ArmGripperManasTrainingService(
                    storeFactory: { ManasMLXModelStore() }
                ).train(request: request)
            }
        }
        let service = await RoArmM1ArmGripperTrainingPipelineService(
            manasTrainingOperation: manasTrainingOperation
        )
        let pipelineResult = try await service.run(request: RoArmM1ArmGripperTrainingPipelineService.Request(
            modelPath: model,
            outputURL: outputURL,
            duration: duration,
            seed: seed,
            includeHindsightRelabels: !noHindsight,
            manasTraining: manasTraining
        ))
        let result = pipelineResult.datasetResult

        print("[roarm-m1-training] goal=\(result.report.goal.goalID)")
        print("[roarm-m1-training] status=\(result.report.status.rawValue)")
        print("[roarm-m1-training] records=\(result.report.recordCount) source=\(result.report.sourceRecordCount) hindsight=\(result.report.hindsightRecordCount)")
        print("[roarm-m1-training] meanAbsErrorRad=\(format(result.report.meanAbsoluteErrorRadians)) maxAbsErrorRad=\(format(result.report.maximumAbsoluteErrorRadians))")
        print("[roarm-m1-training] movementRad=\(format(result.report.movementMagnitudeRadians)) limitViolations=\(result.report.jointLimitViolationCount)")
        print("[roarm-m1-training] output=\(pipelineResult.outputURL.path)")

        guard let manasResult = pipelineResult.manasResult else {
            print("[roarm-m1-training] manas=skipped")
            return
        }

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
