import Foundation
import KuyuTraining

@MainActor
protocol LearningCampaignRunCommanding: AnyObject {
    func startTrainingRun(request: TrainingRunRequest) async throws -> any TrainingRunHandle
    func resumeTrainingRun(request: TrainingResumeRequest) async throws -> any TrainingRunHandle
    func reconnectTrainingRun(artifactRoot: URL) async throws -> (any TrainingRunHandle)?
}

extension LearningCampaignRunCommanding {
    func reconnectTrainingRun(artifactRoot: URL) async throws -> (any TrainingRunHandle)? {
        nil
    }
}

extension CommandSystem: LearningCampaignRunCommanding {}
