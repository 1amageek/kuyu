import KuyuTraining
@testable import KuyuUI
import Testing

@MainActor
@Test(.timeLimit(.minutes(1)))
func simulationViewModelKeepsSelectedTaskAndLearningContractsAligned() {
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))

    model.taskMode = .attitude
    #expect(model.learningCampaignPolicyContract.temporalWindow.observationDimension == 16)
    #expect(model.learningCampaignPolicyContract.actionEncoding == .ctbr)
    #expect(model.learningCampaignActionContract.channels.count == 4)

    model.taskMode = .lift
    #expect(model.learningCampaignPolicyContract.temporalWindow.observationDimension == 64)
    #expect(model.learningCampaignPolicyContract.actionEncoding == .ctbr)
    #expect(model.learningCampaignActionContract.channels.count == 4)

    model.taskMode = .singleLift
    #expect(model.learningCampaignPolicyContract.temporalWindow.observationDimension == 8)
    #expect(model.learningCampaignPolicyContract.actionEncoding == .directMotor)
    #expect(model.learningCampaignActionContract.channels.count == 1)
}
