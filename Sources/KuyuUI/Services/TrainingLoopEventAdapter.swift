import Foundation
import KuyuMLX
import KuyuScenarios
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
            onEvent(.runCompleted(
                iteration: iteration,
                output: KuyAtt1RunOutput(trainingScenarioRunOutput: output),
                score: score
            ))
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
        let classification = TrainingRunResultTerminalClassifier().classify(result: result)
        let failures = classification.accepted ? [] : [classification.reason]
        switch classification.status {
        case .failed, .incomplete:
            onEvent(.failed(message: classification.reason))
        case .accepted, .rejected, .cancelled:
            break
        }
        onEvent(.completed(summary: TrainingLoopSummary(
            iterations: result.metrics.map(\.iteration).max() ?? 0,
            bestScore: scores.max() ?? 0,
            lastScore: scores.last ?? 0,
            passed: classification.accepted,
            failures: failures,
            artifactDirectory: artifactDirectory,
            convergence: result.convergence,
            checkpointDecision: result.checkpointDecision
        )))
    }
}

private extension KuyAtt1RunOutput {
    init(trainingScenarioRunOutput output: TrainingScenarioRunOutput) {
        let evaluations = output.summary.evaluations.map { record in
            ScenarioEvaluation(
                scenarioId: record.scenarioID,
                seed: record.seed,
                passed: record.passed,
                maxOmega: record.maxOmega,
                maxTiltDegrees: record.maxTiltDegrees,
                sustainedViolationSeconds: record.sustainedViolationSeconds,
                recoveryTimeSeconds: record.recoveryTimeSeconds,
                overshootDegrees: record.overshootDegrees,
                hfStabilityScore: record.hfStabilityScore,
                failures: record.failures,
                failureReason: record.failureReason,
                failureTime: record.failureTime
            )
        }
        let replay = ReplayVerification.notPerformed(
            reason: "Training runtime emitted a profile-neutral run output."
        )
        let aggregate = EvaluationAggregate(
            averageRecoveryTime: output.summary.aggregate.averageRecoveryTime,
            worstOvershootDegrees: output.summary.aggregate.worstOvershootDegrees,
            averageHfStabilityScore: output.summary.aggregate.averageHfStabilityScore
        )
        let summary = ValidationSummary(
            suitePassed: output.summary.suitePassed,
            evaluations: evaluations,
            replay: replay,
            manifest: [],
            aggregate: aggregate
        )
        self.init(
            result: SuiteRunResult(
                evaluations: evaluations,
                replay: replay,
                passed: output.summary.suitePassed
            ),
            summary: summary,
            logs: output.logs
        )
    }
}
