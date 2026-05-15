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
