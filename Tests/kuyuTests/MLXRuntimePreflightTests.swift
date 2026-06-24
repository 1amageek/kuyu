import Foundation
import Testing
@testable import KuyuMLX

@Test(.timeLimit(.minutes(1))) func mlxRuntimePreflightRejectsMissingSwiftPMMetallib() throws {
    let executable = "/tmp/kuyu-preflight/.build/arm64-apple-macosx/release/kuyu"

    #expect(throws: MLXRuntimePreflightError.missingMetallib("/tmp/kuyu-preflight/.build/arm64-apple-macosx/release/mlx.metallib")) {
        try MLXRuntimePreflight().check(executablePath: executable)
    }
}

@Test(.timeLimit(.minutes(1))) func mlxRuntimePreflightIgnoresNonSwiftPMExecutables() throws {
    try MLXRuntimePreflight().check(executablePath: "/Applications/Kuyu.app/Contents/MacOS/kuyu")
}

@Test(.timeLimit(.minutes(1))) func mlxRuntimePreflightAcceptsExplicitMetallibPath() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-mlx-preflight-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let metallib = root.appendingPathComponent("mlx.metallib")
    try Data("placeholder".utf8).write(to: metallib)

    try MLXRuntimePreflight().check(metallibURL: metallib, executablePath: nil)
}

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
