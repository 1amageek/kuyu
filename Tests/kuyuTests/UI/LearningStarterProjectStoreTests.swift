import Foundation
import KuyuUI
import Testing

@Test func learningStarterProjectStoreCreatesCompleteStarterProject() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-starter-\(UUID().uuidString)", isDirectory: true)
    let store = LearningStarterProjectStore(
        projectRoot: root,
        now: { Date(timeIntervalSince1970: 1_778_400_000) }
    )

    let project = try store.prepareStarterProject { checkpoint in
        try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
        for fileName in ["model.json", "core.safetensors", "reflex.safetensors", "manas-bundle.json"] {
            let url = checkpoint.appendingPathComponent(fileName)
            try Data(fileName.utf8).write(to: url, options: .atomic)
        }
    }

    #expect(project.projectRoot == root)
    #expect(store.checkpointIsComplete(at: project.sourceCheckpoint))
    #expect(project.artifactRoot.lastPathComponent == "run-1778400000")
    #expect(!FileManager.default.fileExists(atPath: project.artifactRoot.path))
    #expect(try store.artifactRootIsReusable(project.artifactRoot))
}

@Test func learningStarterProjectStoreRejectsIncompleteCheckpointWriter() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-starter-incomplete-\(UUID().uuidString)", isDirectory: true)
    let store = LearningStarterProjectStore(
        projectRoot: root,
        now: { Date(timeIntervalSince1970: 1_778_400_000) }
    )

    #expect(throws: LearningStarterProjectStoreError.self) {
        _ = try store.prepareStarterProject { checkpoint in
            try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
            let url = checkpoint.appendingPathComponent("model.json")
            try Data("{}".utf8).write(to: url, options: .atomic)
        }
    }
}

@Test func learningStarterProjectStoreMakesUniqueRunRoots() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-starter-unique-\(UUID().uuidString)", isDirectory: true)
    let store = LearningStarterProjectStore(
        projectRoot: root,
        now: { Date(timeIntervalSince1970: 1_778_400_000) }
    )

    let first = try store.makeNextRunArtifactRoot()
    try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
    let second = try store.makeNextRunArtifactRoot()

    #expect(first.lastPathComponent == "run-1778400000")
    #expect(second.lastPathComponent == "run-1778400000-2")
}

@Test func learningStarterProjectStoreRegeneratesRequestedSourceCheckpoint() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-starter-regenerate-\(UUID().uuidString)", isDirectory: true)
    let store = LearningStarterProjectStore(
        projectRoot: root,
        now: { Date(timeIntervalSince1970: 1_778_400_000) }
    )

    _ = try store.prepareStarterProject { checkpoint in
        try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
        for fileName in ["model.json", "core.safetensors", "reflex.safetensors", "manas-bundle.json"] {
            let url = checkpoint.appendingPathComponent(fileName)
            try Data("first-\(fileName)".utf8).write(to: url, options: .atomic)
        }
    }

    let project = try store.prepareStarterProject(regenerateSourceCheckpoint: true) { checkpoint in
        try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
        for fileName in ["model.json", "core.safetensors", "reflex.safetensors", "manas-bundle.json"] {
            let url = checkpoint.appendingPathComponent(fileName)
            try Data("second-\(fileName)".utf8).write(to: url, options: .atomic)
        }
    }

    let model = try String(contentsOf: project.sourceCheckpoint.appendingPathComponent("model.json"), encoding: .utf8)
    #expect(model == "second-model.json")
}

@Test func learningStarterProjectStoreDetectsReusableArtifactRoots() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-starter-reusable-\(UUID().uuidString)", isDirectory: true)
    let store = LearningStarterProjectStore(
        projectRoot: root,
        now: { Date(timeIntervalSince1970: 1_778_400_000) }
    )
    let missing = root.appendingPathComponent("missing", isDirectory: true)
    let empty = root.appendingPathComponent("empty", isDirectory: true)
    let used = root.appendingPathComponent("used", isDirectory: true)
    let file = root.appendingPathComponent("file")

    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: used, withIntermediateDirectories: true)
    try Data("artifact".utf8).write(to: used.appendingPathComponent("campaign-status.json"), options: .atomic)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("not a directory".utf8).write(to: file, options: .atomic)

    #expect(try store.artifactRootIsReusable(missing))
    #expect(try store.artifactRootIsReusable(empty))
    #expect(try !store.artifactRootIsReusable(used))
    #expect(try !store.artifactRootIsReusable(file))
}
