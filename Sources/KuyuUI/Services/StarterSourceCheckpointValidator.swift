import Foundation
import KuyuMLX
import KuyuTraining

public struct StarterSourceCheckpointValidationRequest: Sendable {
    public let checkpointURL: URL
    public let robotManifestPath: String
    public let policyContract: LearningProjectPolicyContract
    public let actionContract: LearningProjectActionContract
    public let expectedDriveCount: Int
    public let expectedObservationChannelCount: Int

    public init(
        checkpointURL: URL,
        robotManifestPath: String,
        policyContract: LearningProjectPolicyContract,
        actionContract: LearningProjectActionContract,
        expectedDriveCount: Int,
        expectedObservationChannelCount: Int
    ) {
        self.checkpointURL = checkpointURL
        self.robotManifestPath = robotManifestPath
        self.policyContract = policyContract
        self.actionContract = actionContract
        self.expectedDriveCount = expectedDriveCount
        self.expectedObservationChannelCount = expectedObservationChannelCount
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
            try compatibility.validate(
                ManasMLXStarterSourceCheckpointCompatibilityRequest(
                    checkpointURL: request.checkpointURL,
                    robotManifestPath: request.robotManifestPath,
                    policyContract: request.policyContract,
                    actionContract: request.actionContract,
                    expectedDriveCount: request.expectedDriveCount,
                    expectedObservationChannelCount: request.expectedObservationChannelCount
                )
            )
        } catch {
            throw LearningCampaignLaunchError.invalidConfiguration(
                "starter checkpoint incompatible: \(error)"
            )
        }
    }
}
