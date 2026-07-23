import Foundation
import KuyuTraining

struct LearningCampaignExecutionSnapshot: Sendable, Equatable {
    let runID: TrainingRunID?
    let artifactRoot: URL?
    let isRunning: Bool
    let progressFraction: Double
    let phase: String
    let latestEvent: String?
    let error: String?
    let terminalSummary: TrainingRunSummary?
}
