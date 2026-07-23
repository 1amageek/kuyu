import Foundation
import KuyuMLX
import KuyuMLXTrainingRuntime
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

public struct RunnableProjectAssetPreparationRequest {
    public let projectRootURL: URL
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
        projectRootURL: URL,
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
        self.projectRootURL = projectRootURL
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

public enum RunnableProjectAssetPreparationError: Error, Equatable, LocalizedError, Sendable {
    case refusingExternalCheckpointPath(checkpoint: String, projectRoot: String)

    public var errorDescription: String? {
        switch self {
        case .refusingExternalCheckpointPath(let checkpoint, let projectRoot):
            return "Refusing to replace checkpoint outside project root: \(checkpoint) is not under \(projectRoot)"
        }
    }
}

@MainActor
public protocol RunnableProjectAssetPreparing {
    func prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest) async throws
}

public protocol TemporalCheckpointWriting: Sendable {
    @ManasMLXExecutionActor
    func write(request: ManasMLXTemporalCheckpointWriteRequest) throws -> ManasMLXTemporalCheckpointManifest
}

extension ManasMLXTemporalCheckpointWriter: TemporalCheckpointWriting {}

@MainActor
public struct ManasMLXRunnableProjectAssetPreparer: RunnableProjectAssetPreparing {
    private let modelStoreFactory: @MainActor () -> ManasMLXModelStore
    private let checkpointValidator: any StarterSourceCheckpointValidating
    private let temporalCheckpointWriter: any TemporalCheckpointWriting
    private let directoryPublisher = TransactionalDirectoryPublisher()

    public init(
        modelStoreFactory: @escaping @MainActor () -> ManasMLXModelStore = { ManasMLXModelStore() },
        checkpointValidator: any StarterSourceCheckpointValidating = ManasMLXStarterSourceCheckpointValidator(),
        temporalCheckpointWriter: (any TemporalCheckpointWriting)? = nil
    ) {
        self.modelStoreFactory = modelStoreFactory
        self.checkpointValidator = checkpointValidator
        self.temporalCheckpointWriter = temporalCheckpointWriter ?? ManasMLXTemporalCheckpointWriter()
    }

    public func prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest) async throws {
        try assertCheckpointIsOwned(request.checkpointURL, by: request.projectRootURL)
        try await directoryPublisher.publish(to: request.checkpointURL) { stagingURL in
            let stagingRequest = request.replacingCheckpointURL(stagingURL)
            try await writeCheckpoint(request: stagingRequest)
            try checkpointValidator.validate(request: StarterSourceCheckpointValidationRequest(
                checkpointURL: stagingURL,
                robotManifestPath: request.robotManifestPath,
                policyContract: request.policyContract,
                actionContract: request.actionContract,
                taskMode: request.taskMode,
                observationChannelCountOverride: request.observationChannelCountOverride
            ))
        }
    }

    private func writeCheckpoint(request: RunnableProjectAssetPreparationRequest) async throws {
        let starterContract = try ReferenceQuadrotorStarterCheckpointContractService().contract(
            taskMode: request.taskMode,
            observationChannelCountOverride: request.observationChannelCountOverride,
            directMotorDriveCountOverride: request.driveCount
        )

        if request.policyContract.actionEncoding == .ctbr {
            _ = try await temporalCheckpointWriter.write(request: ManasMLXTemporalCheckpointWriteRequest(
                checkpointURL: request.checkpointURL,
                name: request.displayName,
                policyContract: request.policyContract,
                observationContract: starterContract.observationContract,
                actionContract: request.actionContract,
                embodiment: request.embodiment,
                initializationSeed: starterContract.initializationSeed,
                starterActionMean: starterContract.starterActionMean,
                createdAt: Date(),
                lastTrainedAt: nil
            ))
            return
        }

        let modelStore = modelStoreFactory()
        try await modelStore.initializeDefaultModels(
            observationMode: .runtimeMode(for: request.taskMode),
            driveCount: request.driveCount,
            auxEnabled: request.auxEnabled,
            useQualityGating: request.qualityGatingEnabled,
            embodiment: request.embodiment
        )
        try await modelStore.saveModel(
            to: request.checkpointURL,
            name: request.displayName,
            createdAt: Date(),
            lastTrainedAt: nil
        )
    }

    private func assertCheckpointIsOwned(_ checkpointURL: URL, by projectRootURL: URL) throws {
        let checkpointPath = checkpointURL.standardizedFileURL.resolvingSymlinksInPath().path
        let checkpointParentPath = checkpointURL.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let projectRootPath = projectRootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPrefix = projectRootPath.hasSuffix("/") ? projectRootPath : projectRootPath + "/"
        let checkpointIsOwned = checkpointPath.hasPrefix(rootPrefix) && checkpointPath != projectRootPath
        let parentIsOwned = checkpointParentPath == projectRootPath || checkpointParentPath.hasPrefix(rootPrefix)
        guard checkpointIsOwned, parentIsOwned else {
            throw RunnableProjectAssetPreparationError.refusingExternalCheckpointPath(
                checkpoint: checkpointPath,
                projectRoot: projectRootPath
            )
        }
    }
}

private extension RunnableProjectAssetPreparationRequest {
    func replacingCheckpointURL(_ checkpointURL: URL) -> Self {
        Self(
            projectRootURL: projectRootURL,
            checkpointURL: checkpointURL,
            displayName: displayName,
            robotManifestPath: robotManifestPath,
            embodiment: embodiment,
            taskMode: taskMode,
            driveCount: driveCount,
            observationChannelCountOverride: observationChannelCountOverride,
            auxEnabled: auxEnabled,
            qualityGatingEnabled: qualityGatingEnabled,
            policyContract: policyContract,
            actionContract: actionContract
        )
    }
}
