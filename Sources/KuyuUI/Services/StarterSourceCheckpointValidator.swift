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
    public init() {}

    public func validate(request: StarterSourceCheckpointValidationRequest) throws {
        _ = try ManasMLXE2EPreflight().check(
            robotManifestPath: request.robotManifestPath,
            sourceCheckpointURL: request.checkpointURL,
            requireSourceCheckpoint: true
        )
        if request.policyContract.actionEncoding == .ctbr {
            try validateTemporalPolicyCheckpoint(request: request)
            return
        }
        if let failure = try ManasMLXCheckpointCompatibility(
            expectedDriveCount: request.expectedDriveCount,
            expectedCoreInputSize: request.expectedObservationChannelCount * 4
        ).validate(snapshotURL: request.checkpointURL) {
            throw LearningCampaignLaunchError.invalidConfiguration("starter checkpoint incompatible: \(failure.description)")
        }
    }

    private func validateTemporalPolicyCheckpoint(request: StarterSourceCheckpointValidationRequest) throws {
        let manifestURL = request.checkpointURL.appendingPathComponent("model.json", isDirectory: false)
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ManasMLXTemporalCheckpointManifest.self, from: data)
        let expectedConfig = try ManasMLXTemporalPolicyContractResolver().makeConfig(
            from: request.policyContract,
            action: request.actionContract,
            hiddenSize: manifest.config.hiddenSize
        )
        guard manifest.config == expectedConfig else {
            throw LearningCampaignLaunchError.invalidConfiguration("starter checkpoint incompatible: ctbr policy config mismatch")
        }
    }
}
