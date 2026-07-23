import Foundation
import KuyuMLX
import KuyuScenarios
import KuyuTraining
import KuyuUI
import Testing

@MainActor
@Test func runnableProjectAssetPreparerDelegatesStarterCheckpointValidation() async throws {
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
    let temporalWriter = RecordingTemporalCheckpointWriter()
    let preparer = ManasMLXRunnableProjectAssetPreparer(
        checkpointValidator: validator,
        temporalCheckpointWriter: temporalWriter
    )
    try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
    let sentinel = checkpoint.appendingPathComponent("old-checkpoint.txt", isDirectory: false)
    try Data("old".utf8).write(to: sentinel, options: .atomic)

    try await preparer.prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest(
        projectRootURL: root,
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
    #expect(request.checkpointURL != checkpoint)
    #expect(request.checkpointURL.deletingLastPathComponent() == checkpoint.deletingLastPathComponent())
    #expect(request.robotManifestPath == "robots/reference-quadrotor.json")
    #expect(request.policyContract == policyContract)
    #expect(request.actionContract == actionContract)
    #expect(request.taskMode == .attitude)
    #expect(request.observationChannelCountOverride == 64)
    let writerRequests = await temporalWriter.recordedRequests()
    let writerRequest = try #require(writerRequests.first)
    #expect(writerRequests.count == 1)
    #expect(writerRequest.observationContract == ReferenceQuadrotorLearningContracts.temporalCTBRObservationContract())
    #expect(writerRequest.initializationSeed == 0x4B55_595F_4154_5431)
    #expect(writerRequest.starterActionMean == [0.75, 0.0, 0.0, 0.0])
    #expect(FileManager.default.fileExists(atPath: checkpoint.appendingPathComponent("model.json").path))
    #expect(!FileManager.default.fileExists(atPath: sentinel.path))
}

@MainActor
@Test func runnableProjectAssetPreparerPropagatesStarterCheckpointValidationFailure() async throws {
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
    let temporalWriter = RecordingTemporalCheckpointWriter()
    let preparer = ManasMLXRunnableProjectAssetPreparer(
        checkpointValidator: validator,
        temporalCheckpointWriter: temporalWriter
    )
    try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
    let sentinel = checkpoint.appendingPathComponent("old-checkpoint.txt", isDirectory: false)
    try Data("old".utf8).write(to: sentinel, options: .atomic)

    await #expect(throws: RecordingStarterSourceCheckpointValidator.Failure.self) {
        try await preparer.prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest(
            projectRootURL: root,
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
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "old")
    let siblings = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
    )
    #expect(siblings.count == 1)
    #expect(siblings.first?.lastPathComponent == checkpoint.lastPathComponent)
}

@MainActor
@Test func runnableProjectAssetPreparerRejectsExternalCheckpointReplacement() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-runnable-project-assets-owned-\(UUID().uuidString)", isDirectory: true)
    let external = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-runnable-project-assets-external-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
            try FileManager.default.removeItem(at: external)
        } catch {
            Issue.record("Failed to remove temporary runnable project asset roots: \(error)")
        }
    }

    let checkpoint = external.appendingPathComponent("source.manasbundle", isDirectory: true)
    try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
    let sentinel = checkpoint.appendingPathComponent("sentinel.txt")
    try Data("do-not-delete".utf8).write(to: sentinel, options: .atomic)
    let temporalWriter = RecordingTemporalCheckpointWriter()
    let preparer = ManasMLXRunnableProjectAssetPreparer(
        checkpointValidator: RecordingStarterSourceCheckpointValidator(),
        temporalCheckpointWriter: temporalWriter
    )

    await #expect(throws: RunnableProjectAssetPreparationError.refusingExternalCheckpointPath(
        checkpoint: checkpoint.standardizedFileURL.path,
        projectRoot: root.standardizedFileURL.path
    )) {
        try await preparer.prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest(
            projectRootURL: root,
            checkpointURL: checkpoint,
            displayName: "ui-starter-external",
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
    #expect(FileManager.default.fileExists(atPath: sentinel.path))
}

@MainActor
@Test func runnableProjectAssetPreparerRejectsCheckpointThroughSymlinkedProjectChild() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-runnable-project-assets-symlink-root-\(UUID().uuidString)", isDirectory: true)
    let external = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-runnable-project-assets-symlink-external-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
            try FileManager.default.removeItem(at: external)
        } catch {
            Issue.record("Failed to remove temporary runnable project asset symlink roots: \(error)")
        }
    }

    let link = root.appendingPathComponent("linked", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
    let realCheckpoint = external.appendingPathComponent("source.manasbundle", isDirectory: true)
    try FileManager.default.createDirectory(at: realCheckpoint, withIntermediateDirectories: true)
    let sentinel = realCheckpoint.appendingPathComponent("sentinel.txt", isDirectory: false)
    try Data("do-not-delete".utf8).write(to: sentinel, options: .atomic)
    let checkpointThroughLink = link.appendingPathComponent("source.manasbundle", isDirectory: true)
    let temporalWriter = RecordingTemporalCheckpointWriter()
    let preparer = ManasMLXRunnableProjectAssetPreparer(
        checkpointValidator: RecordingStarterSourceCheckpointValidator(),
        temporalCheckpointWriter: temporalWriter
    )

    await #expect(throws: RunnableProjectAssetPreparationError.refusingExternalCheckpointPath(
        checkpoint: checkpointThroughLink.standardizedFileURL.resolvingSymlinksInPath().path,
        projectRoot: root.standardizedFileURL.resolvingSymlinksInPath().path
    )) {
        try await preparer.prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest(
            projectRootURL: root,
            checkpointURL: checkpointThroughLink,
            displayName: "ui-starter-symlink-external",
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
    #expect(FileManager.default.fileExists(atPath: sentinel.path))
}

@ManasMLXExecutionActor
private final class RecordingTemporalCheckpointWriter: TemporalCheckpointWriting {
    private(set) var requests: [ManasMLXTemporalCheckpointWriteRequest] = []

    func recordedRequests() -> [ManasMLXTemporalCheckpointWriteRequest] {
        requests
    }

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
            actionEncoding: request.policyContract.actionEncoding,
            mlxRandomnessContractID: ManasMLXRandomSeed.executionContractID,
            initializationSeed: request.initializationSeed
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
