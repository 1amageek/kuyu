import Foundation
import Testing
@testable import KuyuMLX

@MainActor
@Test(.timeLimit(.minutes(1))) func manasRuntimeReadinessRejectsMissingRequiredSourceCheckpoint() throws {
    #expect(throws: ManasMLXRuntimeReadinessError.missingCheckpointFile("source checkpoint URL")) {
        try ManasMLXRuntimeReadinessService().report(
            for: ManasMLXRuntimeReadinessRequest(
                robotManifestPath: "",
                sourceCheckpointURL: nil,
                requireSourceCheckpoint: true,
                executablePath: "/Applications/Kuyu.app/Contents/MacOS/kuyu"
            )
        )
    }
}

@MainActor
@Test(.timeLimit(.minutes(1))) func manasRuntimeReadinessRejectsIncompleteSourceCheckpoint() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-manas-runtime-readiness-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove \(root.path): \(error)")
        }
    }

    #expect(throws: ManasMLXRuntimeReadinessError.missingCheckpointFile(root.appendingPathComponent("model.json").path)) {
        try ManasMLXRuntimeReadinessService().report(
            for: ManasMLXRuntimeReadinessRequest(
                robotManifestPath: "",
                sourceCheckpointURL: root,
                executablePath: "/Applications/Kuyu.app/Contents/MacOS/kuyu"
            )
        )
    }
}
