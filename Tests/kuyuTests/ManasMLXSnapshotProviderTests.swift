import Foundation
import KuyuTraining
import ManasCore
import Testing
@testable import KuyuMLX

@Test(.timeLimit(.minutes(1))) func manasMLXSnapshotProviderCreatesWorkerLocalCheckpointCopies() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-mlx-snapshot-provider-\(UUID().uuidString)", isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let workers = root.appendingPathComponent("workers", isDirectory: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary directory \(root.path): \(error)")
        }
    }

    try makeCheckpoint(at: source)

    let provider = ManasMLXSnapshotProvider(
        sourceCheckpointURL: source,
        workerRootURL: workers,
        policyID: "policy-a",
        robotManifestID: "quadref",
        configHash: "config-a"
    )
    let builder = ParallelTrainingWorkerPlanBuilder()

    let plan = try await builder.build(
        runID: "run-a",
        workerCount: 2,
        sourceSnapshot: TrainingBackendSnapshot(
            snapshotID: "source-a",
            checkpointID: "checkpoint-a",
            checkpointURL: source,
            robotManifestID: "quadref",
            configHash: "config-a"
        ),
        rolloutRoot: root.appendingPathComponent("rollouts", isDirectory: true),
        snapshotProvider: provider
    )

    #expect(plan.workerCount == 2)
    #expect(plan.assignments.count == 2)
    #expect(plan.assignments[0].snapshot.workerIndex == 0)
    #expect(plan.assignments[1].snapshot.workerIndex == 1)
    #expect(plan.assignments[0].snapshot.identity.policyID == "policy-a")
    #expect(plan.assignments[0].snapshot.identity.robotManifestID == "quadref")
    #expect(plan.assignments[0].snapshot.identity.configHash == "config-a")
    #expect(plan.assignments[0].snapshot.checkpointURL != plan.assignments[1].snapshot.checkpointURL)

    for assignment in plan.assignments {
        let checkpointURL = assignment.snapshot.checkpointURL
        for fileName in ManasMLXCheckpointFileLayout.current.directMotorRequiredFiles {
            #expect(FileManager.default.fileExists(atPath: checkpointURL.appendingPathComponent(fileName).path))
        }
        #expect(assignment.rolloutShardURL.lastPathComponent == "worker-\(assignment.workerIndex)")
    }
}

@Test(.timeLimit(.minutes(1))) func manasMLXSnapshotProviderRejectsIncompleteCheckpoint() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-mlx-snapshot-provider-incomplete-\(UUID().uuidString)", isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary directory \(root.path): \(error)")
        }
    }

    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let layout = ManasMLXCheckpointFileLayout.current
    try Data("{}".utf8).write(to: source.appendingPathComponent(layout.modelManifestFileName), options: [.atomic])
    try Data("core".utf8).write(to: source.appendingPathComponent(layout.coreWeightsFileName), options: [.atomic])

    let provider = ManasMLXSnapshotProvider(
        sourceCheckpointURL: source,
        workerRootURL: root.appendingPathComponent("workers", isDirectory: true)
    )

    do {
        _ = try await provider.leaseSnapshot(workerIndex: 0)
        Issue.record("Expected incomplete checkpoint to be rejected")
    } catch let error as ManasMLXSnapshotProvider.SnapshotError {
        #expect(error == .missingRequiredFile(source.appendingPathComponent(layout.reflexWeightsFileName)))
    }
}

private func makeCheckpoint(at directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let layout = ManasMLXCheckpointFileLayout.current
    try Data("{}".utf8).write(to: directory.appendingPathComponent(layout.modelManifestFileName), options: [.atomic])
    try Data("core".utf8).write(to: directory.appendingPathComponent(layout.coreWeightsFileName), options: [.atomic])
    try Data("reflex".utf8).write(to: directory.appendingPathComponent(layout.reflexWeightsFileName), options: [.atomic])

    let manifest = ManasModelBundleManifest(
        bundleID: "fixture",
        createdAt: Date(timeIntervalSince1970: 0),
        runtimeContract: ManasModelBundleRuntimeContract(
            embodimentHash: "embodiment",
            configHash: "config",
            observationSchemaID: "trunk-vector",
            driveSemanticsID: "drive-intent"
        ),
        components: [
            ManasModelBundleComponent(
                role: .modelConfig,
                path: layout.modelManifestFileName,
                contentType: "application/json"
            ),
            ManasModelBundleComponent(
                role: .coreWeights,
                path: layout.coreWeightsFileName,
                contentType: "application/vnd.safetensors"
            ),
            ManasModelBundleComponent(
                role: .reflexWeights,
                path: layout.reflexWeightsFileName,
                contentType: "application/vnd.safetensors"
            ),
        ]
    )
    try ManasModelBundleWriter().write(manifest, to: directory)
}
