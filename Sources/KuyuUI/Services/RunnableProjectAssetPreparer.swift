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
    public let observationChannelCountOverride: Int?
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
        observationChannelCountOverride: Int? = nil,
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
        self.observationChannelCountOverride = observationChannelCountOverride
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
public protocol TemporalCheckpointWriting {
    func write(request: ManasMLXTemporalCheckpointWriteRequest) throws -> ManasMLXTemporalCheckpointManifest
}

extension ManasMLXTemporalCheckpointWriter: TemporalCheckpointWriting {}

@MainActor
public struct ManasMLXRunnableProjectAssetPreparer: RunnableProjectAssetPreparing {
    private let modelStore: ManasMLXModelStore
    private let checkpointValidator: any StarterSourceCheckpointValidating
    private let temporalCheckpointWriter: any TemporalCheckpointWriting

    public init(
        modelStore: ManasMLXModelStore,
        checkpointValidator: any StarterSourceCheckpointValidating = ManasMLXStarterSourceCheckpointValidator(),
        temporalCheckpointWriter: (any TemporalCheckpointWriting)? = nil
    ) {
        self.modelStore = modelStore
        self.checkpointValidator = checkpointValidator
        self.temporalCheckpointWriter = temporalCheckpointWriter ?? ManasMLXTemporalCheckpointWriter()
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

        let starterContract = try ReferenceQuadrotorStarterCheckpointContractService().contract(
            taskMode: request.taskMode,
            observationChannelCountOverride: request.observationChannelCountOverride,
            directMotorDriveCountOverride: request.driveCount
        )

        if request.policyContract.actionEncoding == .ctbr {
            _ = try temporalCheckpointWriter.write(request: ManasMLXTemporalCheckpointWriteRequest(
                checkpointURL: request.checkpointURL,
                name: request.displayName,
                policyContract: request.policyContract,
                observationContract: starterContract.observationContract,
                actionContract: request.actionContract,
                embodiment: request.embodiment,
                starterActionMean: starterContract.starterActionMean,
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
            taskMode: request.taskMode,
            observationChannelCountOverride: request.observationChannelCountOverride
        ))
    }

}
