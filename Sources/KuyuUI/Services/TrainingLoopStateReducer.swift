import Foundation
import KuyuScenarios
import KuyuTraining

struct TrainingLoopStateSnapshot: Sendable, Equatable {
    var isLoopRunning: Bool
    var isLoopPaused: Bool
    var loopIteration: Int
    var loopBestScore: Double?
    var loopLastScore: Double?
    var loopStatusMessage: String
    var activeLoopController: ControllerSelection?
    var trainingLearningRate: Double
    var lastTrainingLoss: Double?
    var lastTrainingRunArtifactDirectory: URL?
    var lastConvergenceSummary: ConvergenceSummary?
    var lastCheckpointDecision: CheckpointDecision?
}

struct TrainingLoopStateReducer: Sendable {
    func reduce(
        state: TrainingLoopStateSnapshot,
        event: TrainingLoopEvent
    ) -> TrainingLoopStateSnapshot {
        var next = state
        switch event {
        case .started:
            next.loopStatusMessage = "Running"
        case .iterationStarted(let iteration):
            next.loopIteration = iteration
            next.loopStatusMessage = "Iteration \(iteration)"
        case .runStarted:
            break
        case .teacherRunStarted:
            break
        case .teacherRunCompleted:
            break
        case .runCompleted(let iteration, _, let score):
            next.loopIteration = iteration
            next.loopLastScore = score
            if next.loopBestScore == nil || score > (next.loopBestScore ?? -Double.greatestFiniteMagnitude) {
                next.loopBestScore = score
            }
        case .datasetExportStarted:
            break
        case .datasetExportCompleted:
            break
        case .trainingStarted:
            break
        case .trainingCompleted(_, let result):
            next.lastTrainingLoss = result.finalLoss
        case .reinforcementTrainingCompleted(_, let result):
            next.lastTrainingLoss = result.finalLoss
        case .backoffApplied(let newLearningRate):
            next.trainingLearningRate = newLearningRate
        case .paused:
            next.isLoopPaused = true
            next.loopStatusMessage = "Paused"
        case .resumed:
            next.isLoopPaused = false
            next.loopStatusMessage = "Running"
        case .stopped:
            next.isLoopRunning = false
            next.isLoopPaused = false
            next.loopStatusMessage = "Stopped"
            next.activeLoopController = nil
        case .completed(let summary):
            next.isLoopRunning = false
            next.isLoopPaused = false
            next.activeLoopController = nil
            next.lastTrainingRunArtifactDirectory = summary.artifactDirectory
            next.lastConvergenceSummary = summary.convergence
            next.lastCheckpointDecision = summary.checkpointDecision
            next.loopBestScore = summary.bestScore
            next.loopLastScore = summary.lastScore
            next.loopStatusMessage = summary.passed ? "Completed (passed)" : "Completed"
        case .failed:
            // A launch failure emits only .failed (no .stopped/.completed follows),
            // so the running flags must be released here or the loop wedges.
            next.isLoopRunning = false
            next.isLoopPaused = false
            next.loopStatusMessage = "Failed"
            next.activeLoopController = nil
        }
        return next
    }
}
