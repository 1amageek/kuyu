import Foundation
import KuyuMLX
import KuyuScenarios
import KuyuTraining

public struct StarterSourceCheckpointValidationRequest: Sendable {
    public let checkpointURL: URL
    public let robotManifestPath: String
    public let policyContract: LearningProjectPolicyContract
    public let actionContract: LearningProjectActionContract
    public let taskMode: SimulationTaskMode
    public let observationChannelCountOverride: Int?

    public init(
        checkpointURL: URL,
        robotManifestPath: String,
        policyContract: LearningProjectPolicyContract,
        actionContract: LearningProjectActionContract,
        taskMode: SimulationTaskMode,
        observationChannelCountOverride: Int? = nil
    ) {
        self.checkpointURL = checkpointURL
        self.robotManifestPath = robotManifestPath
        self.policyContract = policyContract
        self.actionContract = actionContract
        self.taskMode = taskMode
        self.observationChannelCountOverride = observationChannelCountOverride
    }
}

@MainActor
public protocol StarterSourceCheckpointValidating {
    func validate(request: StarterSourceCheckpointValidationRequest) throws
}

@MainActor
public struct ManasMLXStarterSourceCheckpointValidator: StarterSourceCheckpointValidating {
    private let compatibility: ManasMLXStarterSourceCheckpointCompatibility

    public init() {
        self.init(compatibility: ManasMLXStarterSourceCheckpointCompatibility())
    }

    public init(compatibility: ManasMLXStarterSourceCheckpointCompatibility) {
        self.compatibility = compatibility
    }

    public func validate(request: StarterSourceCheckpointValidationRequest) throws {
        do {
            let starterContract = try ReferenceQuadrotorStarterCheckpointContractService().contract(
                taskMode: request.taskMode,
                observationChannelCountOverride: request.observationChannelCountOverride
            )
            try compatibility.validate(
                ManasMLXStarterSourceCheckpointCompatibilityRequest(
                    checkpointURL: request.checkpointURL,
                    robotManifestPath: request.robotManifestPath,
                    policyContract: request.policyContract,
                    actionContract: request.actionContract,
                    expectedDriveCount: starterContract.expectedDriveCount,
                    expectedObservationChannelCount: starterContract.expectedObservationChannelCount
                )
            )
        } catch {
            throw LearningCampaignLaunchError.invalidConfiguration(
                "starter checkpoint incompatible: \(error)"
            )
        }
    }
}
