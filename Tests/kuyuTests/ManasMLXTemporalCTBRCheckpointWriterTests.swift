import Foundation
import KuyuPhysics
import KuyuTraining
import MLX
import Testing
@testable import KuyuMLX

@Test func temporalCTBRStarterCheckpointUsesConfiguredCollectiveThrustScale() throws {
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
    let scale = 1.18
    _ = try ManasMLXTemporalCTBRCheckpointWriter().write(request: ManasMLXTemporalCTBRCheckpointWriteRequest(
        checkpointURL: checkpoint,
        name: "ctbr-starter",
        policyContract: .referenceQuadrotorTemporalCTBR(),
        descriptor: nil,
        starterCollectiveThrustScale: scale
    ))

    let arrays = try MLX.loadArrays(url: checkpoint.appendingPathComponent("core.safetensors", isDirectory: false))
    let bias = try #require(arrays["actor.meanHead.bias"])
    let values = bias.asArray(Float.self)
    let thrustCommand = 1.0 / (1.0 + exp(-Double(values[0])))
    let parameters = ReferenceQuadrotorParameters.baseline
    let hoverCommand = parameters.mass * parameters.gravity / (4.0 * parameters.maxThrust)
    let expected = hoverCommand * scale

    #expect(abs(thrustCommand - expected) < 1.0e-5)
    #expect(values[1] == 0)
    #expect(values[2] == 0)
    #expect(values[3] == 0)
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

@Test func temporalCTBRStarterCheckpointRejectsInvalidCollectiveThrustScale() throws {
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
    #expect(throws: ManasMLXTemporalCTBRCheckpointWriter.WriteError.invalidStarterCollectiveThrustScale(0)) {
        _ = try ManasMLXTemporalCTBRCheckpointWriter().write(request: ManasMLXTemporalCTBRCheckpointWriteRequest(
            checkpointURL: checkpoint,
            name: "ctbr-starter",
            policyContract: .referenceQuadrotorTemporalCTBR(),
            descriptor: nil,
            starterCollectiveThrustScale: 0
        ))
    }
}
