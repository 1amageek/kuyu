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
    public let auxEnabled: Bool
    public let qualityGatingEnabled: Bool

    public init(
        checkpointURL: URL,
        displayName: String,
        descriptorPath: String,
        descriptor: RobotDescriptor?,
        taskMode: SimulationTaskMode,
        driveCount: Int?,
        expectedDriveCount: Int,
        auxEnabled: Bool,
        qualityGatingEnabled: Bool
    ) {
        self.checkpointURL = checkpointURL
        self.displayName = displayName
        self.descriptorPath = descriptorPath
        self.descriptor = descriptor
        self.taskMode = taskMode
        self.driveCount = driveCount
        self.expectedDriveCount = expectedDriveCount
        self.auxEnabled = auxEnabled
        self.qualityGatingEnabled = qualityGatingEnabled
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
        try validateCheckpoint(request: request)
    }

    private func validateCheckpoint(request: RunnableProjectAssetPreparationRequest) throws {
        _ = try ManasMLXE2EPreflight().check(
            descriptorPath: request.descriptorPath,
            sourceCheckpointURL: request.checkpointURL,
            requireSourceCheckpoint: true
        )
        if let failure = try ManasMLXCheckpointCompatibility(
            expectedDriveCount: request.expectedDriveCount
        ).validate(snapshotURL: request.checkpointURL) {
            throw LearningCampaignRunError.invalidConfig("starter checkpoint incompatible: \(failure.description)")
        }
    }
}
