import Foundation
import KuyuMLX
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

public struct RunnableProjectAssetPreparationRequest {
    public let checkpointURL: URL
    public let displayName: String
    public let descriptorPath: String
    public let descriptor: RobotDescriptor?
    public let taskMode: SimulationTaskMode
    public let driveCount: Int?
    public let expectedDriveCount: Int
    public let expectedObservationChannelCount: Int
    public let auxEnabled: Bool
    public let qualityGatingEnabled: Bool
    public let policyContract: LearningProjectPolicyContract

    public init(
        checkpointURL: URL,
        displayName: String,
        descriptorPath: String,
        descriptor: RobotDescriptor?,
        taskMode: SimulationTaskMode,
        driveCount: Int?,
        expectedDriveCount: Int,
        expectedObservationChannelCount: Int,
        auxEnabled: Bool,
        qualityGatingEnabled: Bool,
        policyContract: LearningProjectPolicyContract
    ) {
        self.checkpointURL = checkpointURL
        self.displayName = displayName
        self.descriptorPath = descriptorPath
        self.descriptor = descriptor
        self.taskMode = taskMode
        self.driveCount = driveCount
        self.expectedDriveCount = expectedDriveCount
        self.expectedObservationChannelCount = expectedObservationChannelCount
        self.auxEnabled = auxEnabled
        self.qualityGatingEnabled = qualityGatingEnabled
        self.policyContract = policyContract
    }
}

@MainActor
public protocol RunnableProjectAssetPreparing {
    func prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest) throws
}

@MainActor
public struct ManasMLXRunnableProjectAssetPreparer: RunnableProjectAssetPreparing {
    private let modelStore: ManasMLXModelStore

    public init(modelStore: ManasMLXModelStore) {
        self.modelStore = modelStore
    }

    public func prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: request.checkpointURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: request.checkpointURL.path) {
            try fileManager.removeItem(at: request.checkpointURL)
        }

        if request.policyContract.actionEncoding == .ctbr {
            _ = try ManasMLXTemporalCTBRCheckpointWriter().write(request: ManasMLXTemporalCTBRCheckpointWriteRequest(
                checkpointURL: request.checkpointURL,
                name: request.displayName,
                policyContract: request.policyContract,
                descriptor: request.descriptor,
                starterCollectiveThrustScale: starterCollectiveThrustScale(taskMode: request.taskMode),
                createdAt: Date(),
                lastTrainedAt: nil
            ))
        } else {
            try fileManager.createDirectory(at: request.checkpointURL, withIntermediateDirectories: true)
            try modelStore.initializeDefaultModels(
                observationMode: .runtimeMode(for: request.taskMode),
                driveCount: request.driveCount,
                auxEnabled: request.auxEnabled,
                useQualityGating: request.qualityGatingEnabled,
                descriptor: request.descriptor
            )
            try modelStore.saveModel(
                to: request.checkpointURL,
                name: request.displayName,
                createdAt: Date(),
                lastTrainedAt: nil
            )
        }
        try validateCheckpoint(request: request)
    }

    private func starterCollectiveThrustScale(taskMode: SimulationTaskMode) -> Double {
        switch taskMode {
        case .lift:
            return 1.18
        case .attitude:
            return 1.0
        case .singleLift:
            return 1.12
        }
    }

    private func validateCheckpoint(request: RunnableProjectAssetPreparationRequest) throws {
        _ = try ManasMLXE2EPreflight().check(
            descriptorPath: request.descriptorPath,
            sourceCheckpointURL: request.checkpointURL,
            requireSourceCheckpoint: true
        )
        if request.policyContract.actionEncoding != .ctbr {
            if let failure = try ManasMLXCheckpointCompatibility(
                expectedDriveCount: request.expectedDriveCount,
                expectedCoreInputSize: request.expectedObservationChannelCount * 4
            ).validate(snapshotURL: request.checkpointURL) {
                throw LearningCampaignLaunchError.invalidConfiguration("starter checkpoint incompatible: \(failure.description)")
            }
        }
    }
}
