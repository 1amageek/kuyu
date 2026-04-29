import Foundation
import KuyuMLX
import KuyuTraining

enum TrainingLoopEventAdapter {
    static func present(
        event: TrainingRunEvent,
        trainingTemplate: TrainingBackendRequest,
        onEvent: @Sendable (TrainingLoopEvent) -> Void
    ) {
        switch event {
        case .iterationStarted(let iteration):
            onEvent(.iterationStarted(iteration))
            onEvent(.runStarted(iteration: iteration))
        case .suiteCompleted(let iteration, let output, let score):
            onEvent(.runCompleted(iteration: iteration, output: output, score: score))
        case .datasetExported(let iteration, let directory, let count):
            onEvent(.datasetExportStarted(iteration: iteration, path: directory))
            onEvent(.datasetExportCompleted(iteration: iteration, count: count))
        case .trainingCompleted(let iteration, let result):
            onEvent(.trainingStarted(
                iteration: iteration,
                path: trainingTemplate.datasetURL.path,
                epochs: result.epochs,
                learningRate: trainingTemplate.learningRate
            ))
            onEvent(.trainingCompleted(
                iteration: iteration,
                result: TrainingResult(finalLoss: result.finalLoss, epochs: result.epochs)
            ))
        case .reinforcementTrainingCompleted(let iteration, let result):
            onEvent(.reinforcementTrainingCompleted(iteration: iteration, result: result))
        default:
            break
        }
    }

    static func presentCompletion(
        result: TrainingRunResult,
        artifactDirectory: URL,
        onEvent: @Sendable (TrainingLoopEvent) -> Void
    ) {
        let scores = result.metrics
            .filter { $0.kind == .score }
            .map(\.value)
        let failures: [String]
        if let reason = result.manifest.failureReason {
            failures = [reason]
            onEvent(.failed(message: reason))
        } else if !result.convergence.accepted {
            failures = [result.convergence.reason]
        } else {
            failures = []
        }
        onEvent(.completed(summary: TrainingLoopSummary(
            iterations: result.metrics.map(\.iteration).max() ?? 0,
            bestScore: scores.max() ?? 0,
            lastScore: scores.last ?? 0,
            passed: result.convergence.accepted,
            failures: failures,
            artifactDirectory: artifactDirectory,
            convergence: result.convergence,
            checkpointDecision: result.checkpointDecision
        )))
    }
}
