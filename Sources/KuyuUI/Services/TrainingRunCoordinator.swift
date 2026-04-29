import Foundation
import KuyuCore
import KuyuMLX
import KuyuPhysics
import KuyuScenarios

struct TrainingRunPreparationInput {
    let controllerSelection: ControllerSelection
    let taskMode: SimulationTaskMode
    let kp: Double
    let kd: Double
    let yawDamping: Double
    let hoverThrustScale: Double
    let cutPeriodSteps: UInt64
    let determinismSelection: DeterminismSelection
    let modelDescriptorPath: String
    let overrideParameters: ReferenceQuadrotorParameters?
    let descendingIntent: ResolvedDescendingIntent
    let datasetDirectory: String
    let trainingEpochs: Int
    let trainingSequenceLength: Int
    let trainingLearningRate: Double
    let trainingUseAux: Bool
    let trainingUseQualityGating: Bool
    let loopMaxIterations: Int
    let loopEvaluationInterval: Int
    let loopStopOnPass: Bool
    let loopPatience: Int
    let loopMinDelta: Double
    let loopMaxFailures: Int
    let loopAllowAutoBackoff: Bool
}

struct TrainingRunPreparation {
    let controller: ControllerSelection
    let runRequest: SimulationRunRequest
    let trainingTemplate: TrainingRequest
    let loopConfig: TrainingLoopConfig
    let datasetRoot: URL
}

struct TrainingRunCoordinator {
    func prepare(input: TrainingRunPreparationInput) throws -> TrainingRunPreparation {
        let gains = try ImuRateDampingCutGains(
            kp: input.kp,
            kd: input.kd,
            yawDamping: input.yawDamping,
            hoverThrustScale: input.hoverThrustScale
        )
        let determinism = try input.determinismSelection.makeConfig()
        let controller: ControllerSelection = input.controllerSelection == .manasMLX
            ? input.controllerSelection
            : .manasMLX
        let datasetRoot = datasetRoot(from: input.datasetDirectory)
        let runRequest = SimulationRunRequest(
            controller: controller,
            taskMode: input.taskMode,
            gains: gains,
            cutPeriodSteps: input.cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            modelDescriptorPath: input.modelDescriptorPath,
            overrideParameters: input.overrideParameters,
            useAux: input.trainingUseAux,
            useQualityGating: input.trainingUseQualityGating,
            descendingVector: input.descendingIntent.vector,
            descendingProgram: input.descendingIntent.program
        )
        let trainingTemplate = TrainingRequest(
            datasetURL: datasetRoot,
            sequenceLength: input.trainingSequenceLength,
            epochs: input.trainingEpochs,
            learningRate: input.trainingLearningRate,
            useAux: input.trainingUseAux,
            useQualityGating: input.trainingUseQualityGating
        )
        let loopConfig = TrainingLoopConfig(
            maxIterations: input.loopMaxIterations,
            evaluationInterval: input.loopEvaluationInterval,
            stopOnPass: input.loopStopOnPass,
            patience: input.loopPatience,
            minDelta: input.loopMinDelta,
            maxConsecutiveFailures: input.loopMaxFailures,
            allowAutoBackoff: input.loopAllowAutoBackoff,
            enableDatasetExport: true,
            enableTraining: true
        )
        return TrainingRunPreparation(
            controller: controller,
            runRequest: runRequest,
            trainingTemplate: trainingTemplate,
            loopConfig: loopConfig,
            datasetRoot: datasetRoot
        )
    }

    private func datasetRoot(from configuredDirectory: String) -> URL {
        let trimmed = configuredDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-loop-\(UUID().uuidString)", isDirectory: true)
        }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
            .appendingPathComponent("loop-\(UUID().uuidString)", isDirectory: true)
    }
}
