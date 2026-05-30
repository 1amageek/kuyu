import Foundation
import ManasCore
import ManasMLXModels
import Testing
@testable import KuyuMLX

@Test(.timeLimit(.minutes(1))) func checkpointCompatibilityRejectsSingleDriveSnapshotForQuadRegression() throws {
    let root = try makeCheckpointRoot(
        driveCount: 1,
        reflexConfig: ManasMLXReflexConfig(inputSize: 8, driveCount: 1),
        writeReflex: true
    )
    defer { removeTemporaryRoot(root) }

    let failure = try ManasMLXCheckpointCompatibility(expectedDriveCount: 4)
        .validate(snapshotURL: root)
    #expect(failure == .incompatibleDriveCount(expected: 4, actual: 1))
}

@Test(.timeLimit(.minutes(1))) func checkpointCompatibilityAcceptsSingleDriveSnapshotForSingleLiftRegression() throws {
    let root = try makeCheckpointRoot(
        driveCount: 1,
        reflexConfig: ManasMLXReflexConfig(inputSize: 8, driveCount: 1),
        writeReflex: true
    )
    defer { removeTemporaryRoot(root) }

    let failure = try ManasMLXCheckpointCompatibility(expectedDriveCount: 1)
        .validate(snapshotURL: root)
    #expect(failure == nil)
}

@Test(.timeLimit(.minutes(1))) func checkpointCompatibilityRejectsMissingReflexConfig() throws {
    let root = try makeCheckpointRoot(
        driveCount: 4,
        reflexConfig: nil,
        writeReflex: true
    )
    defer { removeTemporaryRoot(root) }

    let failure = try ManasMLXCheckpointCompatibility(expectedDriveCount: 4)
        .validate(snapshotURL: root)
    #expect(failure == .missingReflexConfig)
}

@Test(.timeLimit(.minutes(1))) func checkpointCompatibilityRejectsMissingReflexCheckpoint() throws {
    let root = try makeCheckpointRoot(
        driveCount: 4,
        reflexConfig: ManasMLXReflexConfig(inputSize: 6, driveCount: 4),
        writeReflex: false
    )
    defer { removeTemporaryRoot(root) }

    let failure = try ManasMLXCheckpointCompatibility(expectedDriveCount: 4)
        .validate(snapshotURL: root)
    #expect(failure == .missingReflexCheckpoint(root.appendingPathComponent("reflex.safetensors")))
}

@Test(.timeLimit(.minutes(1))) func checkpointCompatibilityAcceptsMatchingSnapshotMetadata() throws {
    let root = try makeCheckpointRoot(
        driveCount: 4,
        reflexConfig: ManasMLXReflexConfig(inputSize: 6, driveCount: 4),
        writeReflex: true
    )
    defer { removeTemporaryRoot(root) }

    let failure = try ManasMLXCheckpointCompatibility(expectedDriveCount: 4)
        .validate(snapshotURL: root)
    #expect(failure == nil)
}

@Test(.timeLimit(.minutes(1))) func checkpointBiasCalibratorRejectsNonFiniteRawBiasDeltaBeforeWritingOutput() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-bias-calibrator-\(UUID().uuidString)", isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let output = root.appendingPathComponent("output", isDirectory: true)
    defer { removeTemporaryRoot(root) }

    do {
        _ = try ManasMLXCheckpointBiasCalibrator().calibrate(
            sourceCheckpointURL: source,
            outputCheckpointURL: output,
            rawBiasDelta: .infinity
        )
        Issue.record("Expected non-finite raw bias delta to reject.")
    } catch ManasMLXCheckpointBiasCalibratorError.nonFiniteRawBiasDelta {
        #expect(!FileManager.default.fileExists(atPath: output.path))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private func makeCheckpointRoot(
    driveCount: Int,
    reflexConfig: ManasMLXReflexConfig?,
    writeReflex: Bool
) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-checkpoint-compat-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let manifest = ManasMLXModelManifest(
        name: "compatibility-smoke",
        createdAt: Date(timeIntervalSince1970: 0),
        lastTrainedAt: nil,
        coreConfig: ManasMLXCoreConfig(
            inputSize: driveCount == 1 ? 32 : 24,
            embeddingSize: 8,
            fastHiddenSize: 8,
            slowHiddenSize: 4,
            driveCount: driveCount,
            auxSize: 0
        ),
        reflexConfig: reflexConfig
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: root.appendingPathComponent("model.json"), options: [.atomic])
    try Data("core".utf8).write(to: root.appendingPathComponent("core.safetensors"), options: [.atomic])
    if writeReflex {
        try Data("reflex".utf8).write(to: root.appendingPathComponent("reflex.safetensors"), options: [.atomic])
    }
    if reflexConfig != nil, writeReflex {
        let bundleManifest = try ManasMLXModelBundleManifestBuilder().build(
            bundleID: "compatibility-smoke",
            createdAt: Date(timeIntervalSince1970: 0),
            manifest: manifest,
            embodiment: nil,
            checkpointRoot: root
        )
        try ManasModelBundleWriter().write(bundleManifest, to: root)
    }
    return root
}

private func removeTemporaryRoot(_ root: URL) {
    guard FileManager.default.fileExists(atPath: root.path) else {
        return
    }
    do {
        try FileManager.default.removeItem(at: root)
    } catch {
        Issue.record("Failed to remove temporary directory \(root.path): \(error)")
    }
}
