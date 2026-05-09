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
        descriptor: nil
    )
    let manifest = try store.saveModel(to: directory, name: "single-drive-starter")

    #expect(manifest.coreConfig.driveCount == 1)
    #expect(manifest.reflexConfig?.driveCount == 1)
    #expect(try ManasMLXCheckpointCompatibility(expectedDriveCount: 1).validate(snapshotURL: directory) == nil)
    #expect(
        try ManasMLXCheckpointCompatibility(expectedDriveCount: 4).validate(snapshotURL: directory)
            == .incompatibleDriveCount(expected: 4, actual: 1)
    )
}

@MainActor
@Test(
    .enabled(if: mlxSaveLoadSmokeEnabled),
    .timeLimit(.minutes(1))
)
func trainedCoreCheckpointIncludesReflexSnapshotForRollout() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-trained-core-checkpoint-\(UUID().uuidString)", isDirectory: true)
    let datasetRoot = root.appendingPathComponent("dataset", isDirectory: true)
    let checkpointRoot = root.appendingPathComponent("checkpoint", isDirectory: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary model directory \(root.path): \(error)")
        }
    }

    let request = SimulationRunRequest(
        controller: .teacherBaseline,
        taskMode: .singleLift,
        gains: try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2),
        cutPeriodSteps: 2,
        noise: .zero,
        determinism: try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline),
        modelDescriptorPath: "",
        overrideParameters: nil,
        useAux: false,
        useQualityGating: true
    )
    let output = try await KuyuSingleLiftTeacherDatasetRunner().run(
        request: request,
        parameters: .baseline,
        schedule: try SimulationSchedule.baseline(cutPeriodSteps: 2)
    )
    _ = try TrainingDatasetExporter().write(output: output, to: datasetRoot)

    let store = ManasMLXModelStore()
    _ = try await store.trainCore(
        datasetURL: datasetRoot,
        sequenceLength: 8,
        learningRate: 0.0001,
        epochs: 1,
        useAux: false,
        useQualityGating: true,
        maxBatches: 1
    )
    let manifest = try store.saveModel(to: checkpointRoot, name: "trained-core-smoke")

    #expect(manifest.reflexConfig != nil)
    #expect(FileManager.default.fileExists(atPath: checkpointRoot.appendingPathComponent("model.json").path))
    #expect(FileManager.default.fileExists(atPath: checkpointRoot.appendingPathComponent("core.safetensors").path))
    #expect(FileManager.default.fileExists(atPath: checkpointRoot.appendingPathComponent("reflex.safetensors").path))
    #expect(FileManager.default.fileExists(atPath: checkpointRoot.appendingPathComponent("manas-bundle.json").path))
}

#if Xcode
private let mlxSaveLoadSmokeEnabled = true
#else
private let mlxSaveLoadSmokeEnabled = false
#endif
