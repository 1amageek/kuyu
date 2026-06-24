import Foundation
import KuyuMLX
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

public struct RunnableProjectAssetPreparationRequest {
    public let checkpointURL: URL
    public let displayName: String
    public let robotManifestPath: String
    public let embodiment: EmbodimentContract?
    public let taskMode: SimulationTaskMode
    public let driveCount: Int?
    public let expectedDriveCount: Int
    public let expectedObservationChannelCount: Int
    public let auxEnabled: Bool
    public let qualityGatingEnabled: Bool
    public let policyContract: LearningProjectPolicyContract
    public let actionContract: LearningProjectActionContract

    public init(
        checkpointURL: URL,
        displayName: String,
        robotManifestPath: String,
        embodiment: EmbodimentContract?,
        taskMode: SimulationTaskMode,
        driveCount: Int?,
        expectedDriveCount: Int,
        expectedObservationChannelCount: Int,
        auxEnabled: Bool,
        qualityGatingEnabled: Bool,
        policyContract: LearningProjectPolicyContract,
        actionContract: LearningProjectActionContract
    ) {
        self.checkpointURL = checkpointURL
        self.displayName = displayName
        self.robotManifestPath = robotManifestPath
        self.embodiment = embodiment
        self.taskMode = taskMode
        self.driveCount = driveCount
        self.expectedDriveCount = expectedDriveCount
        self.expectedObservationChannelCount = expectedObservationChannelCount
        self.auxEnabled = auxEnabled
        self.qualityGatingEnabled = qualityGatingEnabled
        self.policyContract = policyContract
        self.actionContract = actionContract
    }
}

@MainActor
public protocol RunnableProjectAssetPreparing {
    func prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest) throws
}

@MainActor
public struct ManasMLXRunnableProjectAssetPreparer: RunnableProjectAssetPreparing {
    private let modelStore: ManasMLXModelStore
    private let checkpointValidator: any StarterSourceCheckpointValidating

    public init(
        modelStore: ManasMLXModelStore,
        checkpointValidator: any StarterSourceCheckpointValidating = ManasMLXStarterSourceCheckpointValidator()
    ) {
        self.modelStore = modelStore
        self.checkpointValidator = checkpointValidator
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
            _ = try ManasMLXTemporalCheckpointWriter().write(request: ManasMLXTemporalCheckpointWriteRequest(
                checkpointURL: request.checkpointURL,
                name: request.displayName,
                policyContract: request.policyContract,
                observationContract: ReferenceQuadrotorLearningContracts.temporalCTBRObservationContract(),
                actionContract: request.actionContract,
                embodiment: request.embodiment,
                starterActionMean: starterActionMean(taskMode: request.taskMode),
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
                embodiment: request.embodiment
            )
            try modelStore.saveModel(
                to: request.checkpointURL,
                name: request.displayName,
                createdAt: Date(),
                lastTrainedAt: nil
            )
        }
        try checkpointValidator.validate(request: StarterSourceCheckpointValidationRequest(
            checkpointURL: request.checkpointURL,
            robotManifestPath: request.robotManifestPath,
            policyContract: request.policyContract,
            actionContract: request.actionContract,
            expectedDriveCount: request.expectedDriveCount,
            expectedObservationChannelCount: request.expectedObservationChannelCount
        ))
    }

    private func starterActionMean(taskMode: SimulationTaskMode) -> [Double] {
        switch taskMode {
        case .lift:
            return [1.0, 0.0, 0.0, 0.0]
        case .attitude:
            return [0.75, 0.0, 0.0, 0.0]
        case .singleLift:
            return [0.9, 0.0, 0.0, 0.0]
        }
    }

}
