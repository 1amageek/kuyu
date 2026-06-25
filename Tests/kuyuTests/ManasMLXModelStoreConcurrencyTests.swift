import Foundation
import Testing
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTraining
@testable import KuyuMLX

@MainActor
@Test(.timeLimit(.minutes(1))) func modelStoreRejectsReentrantAccessWhileRunIsSuspended() async throws {
    let store = ManasMLXModelStore()
    let control = SimulationControl()
    await control.requestPause()

    let runTask = Task { @MainActor in
        try await store.holdExclusiveForTesting(control: control)
    }

    try await Task.sleep(nanoseconds: 50_000_000)

    do {
        _ = try store.makeManifest()
        #expect(Bool(false), "Expected makeManifest to reject reentrant access")
    } catch let error as ModelStoreError {
        #expect(error == .busy)
    }

    await control.requestStop()
    do {
        _ = try await runTask.value
        #expect(Bool(false), "Expected suspended run to stop with cancellation")
    } catch is CancellationError {
    }
}

@MainActor
@Test(
    .enabled(if: mlxSaveLoadSmokeEnabled),
    .timeLimit(.minutes(1))
)
func modelStoreSavesAndLoadsManifestAndTensorFiles() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-model-store-\(UUID().uuidString)", isDirectory: true)
    defer {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Failed to remove temporary model directory \(directory.path): \(error)")
        }
    }

    let store = ManasMLXModelStore()
    store.initializeModelsForTesting(
        inputSize: 16,
        driveCount: 4,
        auxEnabled: true,
        reflexInputSize: 6
    )

    let savedManifest = try store.saveModel(to: directory, name: "store-smoke")
    #expect(savedManifest.name == "store-smoke")
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("model.json").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("core.safetensors").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("reflex.safetensors").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("manas-bundle.json").path))

    let loadedStore = ManasMLXModelStore()
    let loadedManifest = try loadedStore.loadModel(from: directory)
    #expect(loadedManifest.name == savedManifest.name)
    #expect(loadedManifest.coreConfig == savedManifest.coreConfig)
    #expect(loadedManifest.reflexConfig == savedManifest.reflexConfig)
}

@MainActor
@Test(
    .enabled(if: mlxSaveLoadSmokeEnabled),
    .timeLimit(.minutes(1))
)
func modelStoreInferenceUsesLoadedCheckpointAuxContract() throws {
    let store = ManasMLXModelStore()
    store.initializeModelsForTesting(
        inputSize: 32,
        driveCount: 1,
        auxEnabled: false,
        reflexInputSize: 8
    )

    #expect(store.effectiveInferenceAuxEnabledForTesting(requested: true) == false)
    #expect(store.effectiveInferenceAuxEnabledForTesting(requested: false) == false)
}

@MainActor
@Test(
    .enabled(if: mlxSaveLoadSmokeEnabled),
    .timeLimit(.minutes(1))
)
func modelStoreInitializesSingleDriveStarterCheckpoint() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-single-drive-starter-\(UUID().uuidString)", isDirectory: true)
    defer {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Failed to remove temporary model directory \(directory.path): \(error)")
        }
    }

    let store = ManasMLXModelStore()
    try store.initializeDefaultModels(
        observationMode: .runtimeMode(for: .singleLift),
        driveCount: 1,
        auxEnabled: true,
        useQualityGating: true,
        embodiment: nil
    )
    let manifest = try store.saveModel(to: directory, name: "single-drive-starter")

    #expect(manifest.coreConfig.driveCount == 1)
    #expect(manifest.reflexConfig?.driveCount == 1)
    let checkpointPath = directory.path
    let savedDriveCount = manifest.coreConfig.driveCount
    let compatibility = ManasMLXStarterSourceCheckpointCompatibility(
        preflight: { _ in },
        directMotorCompatibility: { request in
            guard request.checkpointURL.path == checkpointPath else {
                return .invalidModelBundle("unexpected-checkpoint-url")
            }
            guard request.expectedDriveCount == savedDriveCount else {
                return .incompatibleDriveCount(
                    expected: request.expectedDriveCount,
                    actual: savedDriveCount
                )
            }
            return nil
        },
        temporalManifestLoader: { _ in
            throw StarterCheckpointCompatibilityUnexpectedCall.temporalManifest
        },
        temporalConfigResolver: { _, _, _ in
            throw StarterCheckpointCompatibilityUnexpectedCall.temporalConfig
        }
    )
    try compatibility.validate(singleDriveStarterRequest(checkpointURL: directory, expectedDriveCount: 1))
    do {
        try compatibility.validate(singleDriveStarterRequest(checkpointURL: directory, expectedDriveCount: 4))
        Issue.record("Expected starter checkpoint compatibility service to reject drive mismatch.")
    } catch ManasMLXStarterSourceCheckpointCompatibilityError.directMotorIncompatible(let reason) {
        #expect(reason.contains("incompatible-checkpoint-drive-count"))
    }
}

private func singleDriveStarterRequest(
    checkpointURL: URL,
    expectedDriveCount: Int
) -> ManasMLXStarterSourceCheckpointCompatibilityRequest {
    let action = LearningProjectActionContract(
        schemaID: "single-drive-direct-motor-v1",
        kind: .continuous,
        driveCount: expectedDriveCount,
        actuatorCount: expectedDriveCount,
        isBounded: true,
        channels: LearningProjectActionContract.indexedBoundedChannels(
            prefix: "drive",
            count: expectedDriveCount,
            unit: nil,
            lowerBound: -1,
            upperBound: 1,
            transform: .tanh
        )
    )
    return ManasMLXStarterSourceCheckpointCompatibilityRequest(
        checkpointURL: checkpointURL,
        robotManifestPath: "/tmp/reference-single-drive.json",
        policyContract: .simpleFeedForward(
            observationDimension: 8,
            actionDimension: expectedDriveCount,
            actionEncoding: .directMotor
        ),
        actionContract: action,
        expectedDriveCount: expectedDriveCount,
        expectedObservationChannelCount: 8
    )
}

private enum StarterCheckpointCompatibilityUnexpectedCall: Error {
    case temporalManifest
    case temporalConfig
}

private let mlxSaveLoadSmokeEnabled =
    ProcessInfo.processInfo.environment["KUYU_MLX_RUN_MODEL_STORE_SMOKE"] == "1"
