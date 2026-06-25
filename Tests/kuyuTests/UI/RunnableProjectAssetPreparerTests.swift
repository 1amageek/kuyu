import Foundation
import KuyuMLX
import KuyuScenarios
import KuyuTraining
import KuyuUI
import Testing

@MainActor
@Test func runnableProjectAssetPreparerDelegatesStarterCheckpointValidation() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-runnable-project-assets-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary runnable project asset root: \(error)")
        }
    }

    let checkpoint = root.appendingPathComponent("source.manasbundle", isDirectory: true)
    let policyContract = ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract()
    let actionContract = ReferenceQuadrotorLearningContracts.bodyRateActionContract()
    let validator = RecordingStarterSourceCheckpointValidator()
    let preparer = ManasMLXRunnableProjectAssetPreparer(
        modelStore: ManasMLXModelStore(),
        checkpointValidator: validator,
        temporalCheckpointWriter: RecordingTemporalCheckpointWriter()
    )

    try preparer.prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest(
        checkpointURL: checkpoint,
        displayName: "ui-starter",
        robotManifestPath: "robots/reference-quadrotor.json",
        embodiment: nil,
        taskMode: .attitude,
        driveCount: nil,
        observationChannelCountOverride: 64,
        auxEnabled: false,
        qualityGatingEnabled: true,
        policyContract: policyContract,
        actionContract: actionContract
    ))

    let request = try #require(validator.requests.first)
    #expect(validator.requests.count == 1)
    #expect(request.checkpointURL == checkpoint)
    #expect(request.robotManifestPath == "robots/reference-quadrotor.json")
    #expect(request.policyContract == policyContract)
    #expect(request.actionContract == actionContract)
    #expect(request.taskMode == .attitude)
    #expect(request.observationChannelCountOverride == 64)
    #expect(FileManager.default.fileExists(atPath: checkpoint.appendingPathComponent("model.json").path))
}

@MainActor
@Test func runnableProjectAssetPreparerPropagatesStarterCheckpointValidationFailure() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-runnable-project-assets-reject-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary runnable project asset root: \(error)")
        }
    }

    let checkpoint = root.appendingPathComponent("source.manasbundle", isDirectory: true)
    let validator = RecordingStarterSourceCheckpointValidator(error: RecordingStarterSourceCheckpointValidator.Failure())
    let preparer = ManasMLXRunnableProjectAssetPreparer(
        modelStore: ManasMLXModelStore(),
        checkpointValidator: validator,
        temporalCheckpointWriter: RecordingTemporalCheckpointWriter()
    )

    #expect(throws: RecordingStarterSourceCheckpointValidator.Failure.self) {
        try preparer.prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest(
            checkpointURL: checkpoint,
            displayName: "ui-starter-reject",
            robotManifestPath: "robots/reference-quadrotor.json",
            embodiment: nil,
            taskMode: .attitude,
            driveCount: nil,
            observationChannelCountOverride: 64,
            auxEnabled: false,
            qualityGatingEnabled: true,
            policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
            actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract()
        ))
    }
    #expect(validator.requests.count == 1)
}

@MainActor
private final class RecordingTemporalCheckpointWriter: TemporalCheckpointWriting {
    private(set) var requests: [ManasMLXTemporalCheckpointWriteRequest] = []

    func write(request: ManasMLXTemporalCheckpointWriteRequest) throws -> ManasMLXTemporalCheckpointManifest {
        requests.append(request)
        try FileManager.default.createDirectory(at: request.checkpointURL, withIntermediateDirectories: true)
        let config = try ManasMLXTemporalPolicyContractResolver().makeConfig(
            from: request.policyContract,
            action: request.actionContract,
            hiddenSize: request.hiddenSize
        )
        let manifest = ManasMLXTemporalCheckpointManifest(
            name: request.name,
            createdAt: request.createdAt,
            lastTrainedAt: request.lastTrainedAt,
            config: config,
            observationSchemaID: request.observationContract.schemaID,
            actionSchemaID: request.actionContract.schemaID,
            actionEncoding: request.policyContract.actionEncoding
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: request.checkpointURL.appendingPathComponent(ManasMLXCheckpointFileLayout.current.modelManifestFileName),
            options: .atomic
        )
        return manifest
    }
}

@MainActor
private final class RecordingStarterSourceCheckpointValidator: StarterSourceCheckpointValidating {
    struct Failure: Error {}

    private(set) var requests: [StarterSourceCheckpointValidationRequest] = []
    private let error: (any Error)?

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func validate(request: StarterSourceCheckpointValidationRequest) throws {
        requests.append(request)
        if let error {
            throw error
        }
    }
}
