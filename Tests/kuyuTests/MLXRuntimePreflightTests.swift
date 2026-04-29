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
@Test(.timeLimit(.minutes(1))) func manasE2EPreflightRejectsMissingRequiredSourceCheckpoint() throws {
    #expect(throws: ManasMLXE2EPreflightError.missingCheckpointFile("source checkpoint URL")) {
        try ManasMLXE2EPreflight().check(
            descriptorPath: "",
            sourceCheckpointURL: nil,
            requireSourceCheckpoint: true,
            executablePath: "/Applications/Kuyu.app/Contents/MacOS/kuyu"
        )
    }
}

@MainActor
@Test(.timeLimit(.minutes(1))) func manasE2EPreflightRejectsIncompleteSourceCheckpoint() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-manas-e2e-preflight-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove \(root.path): \(error)")
        }
    }

    #expect(throws: ManasMLXE2EPreflightError.missingCheckpointFile(root.appendingPathComponent("model.json").path)) {
        try ManasMLXE2EPreflight().check(
            descriptorPath: "",
            sourceCheckpointURL: root,
            executablePath: "/Applications/Kuyu.app/Contents/MacOS/kuyu"
        )
    }
}
