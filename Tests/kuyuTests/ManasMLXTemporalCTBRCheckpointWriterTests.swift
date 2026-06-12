import Foundation
import KuyuPhysics
import KuyuTraining
import MLX
import Testing
@testable import KuyuMLX

@Test func temporalCheckpointWriterInitializesConfiguredStarterActionMean() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("temporal-ctbr-writer-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary checkpoint root: \(error)")
        }
    }

    let checkpoint = root.appendingPathComponent("source.manasbundle", isDirectory: true)
    let starterActionMean = [0.75, 0.1, -0.2, 0.3]
    _ = try ManasMLXTemporalCheckpointWriter().write(request: ManasMLXTemporalCheckpointWriteRequest(
        checkpointURL: checkpoint,
        name: "ctbr-starter",
        policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
        observationContract: ReferenceQuadrotorLearningContracts.temporalCTBRObservationContract(),
        actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
        embodiment: nil,
        starterActionMean: starterActionMean
    ))

    let arrays = try MLX.loadArrays(url: checkpoint.appendingPathComponent("core.safetensors", isDirectory: false))
    let bias = try #require(arrays["actor.meanHead.bias"])
    let values = bias.asArray(Float.self)
    let thrustCommand = 1.0 / (1.0 + exp(-Double(values[0])))
    let rollRate = tanh(Double(values[1]))
    let pitchRate = tanh(Double(values[2]))
    let yawRate = tanh(Double(values[3]))

    #expect(abs(thrustCommand - starterActionMean[0]) < 1.0e-5)
    #expect(abs(rollRate - starterActionMean[1]) < 1.0e-5)
    #expect(abs(pitchRate - starterActionMean[2]) < 1.0e-5)
    #expect(abs(yawRate - starterActionMean[3]) < 1.0e-5)
}

@Test func temporalCTBRTemporaryCheckpointURLIsNotHidden() throws {
    let id = try #require(UUID(uuidString: "1298D3DD-9A87-40D8-B0D1-E419211CC5B6"))
    let root = URL(fileURLWithPath: "/tmp/kuyu-ctbr-writer", isDirectory: true)
    let checkpoint = root.appendingPathComponent("source.manasbundle", isDirectory: true)
    let temporary = ManasMLXTemporaryBundleURL.makeSiblingURL(for: checkpoint, id: id)

    #expect(temporary.deletingLastPathComponent() == root)
    #expect(temporary.lastPathComponent == "source-writing-1298D3DD-9A87-40D8-B0D1-E419211CC5B6.writing")
    #expect(!temporary.lastPathComponent.hasPrefix("."))
    #expect(temporary.pathExtension == "writing")
}

@Test func temporalCTBRTemporaryCheckpointRemovesStaleSiblings() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("temporal-ctbr-writer-sweep-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary checkpoint root: \(error)")
        }
    }

    let id = try #require(UUID(uuidString: "1298D3DD-9A87-40D8-B0D1-E419211CC5B6"))
    let checkpoint = root.appendingPathComponent("source.manasbundle", isDirectory: true)
    let stale = ManasMLXTemporaryBundleURL.makeSiblingURL(for: checkpoint, id: id)
    let unrelated = root.appendingPathComponent("other-writing-\(id.uuidString).writing", isDirectory: true)
    try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

    try ManasMLXTemporaryBundleURL.removeStaleSiblings(
        for: checkpoint,
        olderThan: 0,
        now: Date(),
        fileManager: .default
    )

    #expect(!FileManager.default.fileExists(atPath: stale.path))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
}

@Test func temporalCheckpointWriterRejectsInvalidStarterActionMeanCount() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("temporal-ctbr-writer-invalid-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary checkpoint root: \(error)")
        }
    }

    let checkpoint = root.appendingPathComponent("source.manasbundle", isDirectory: true)
    #expect(throws: ManasMLXTemporalCheckpointWriter.WriteError.invalidStarterActionMeanCount(expected: 4, actual: 1)) {
        _ = try ManasMLXTemporalCheckpointWriter().write(request: ManasMLXTemporalCheckpointWriteRequest(
            checkpointURL: checkpoint,
            name: "ctbr-starter",
            policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
            observationContract: ReferenceQuadrotorLearningContracts.temporalCTBRObservationContract(),
            actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
            embodiment: nil,
            starterActionMean: [0.5]
        ))
    }
}
