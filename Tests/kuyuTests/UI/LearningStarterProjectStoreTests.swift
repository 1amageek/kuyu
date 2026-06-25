import Foundation
import KuyuMLX
import KuyuTraining
import KuyuUI
import Testing

@Test func learningStarterProjectStoreCreatesCompleteStarterProject() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-starter-\(UUID().uuidString)", isDirectory: true)
    let store = LearningStarterProjectStore(
        projectRoot: root,
        now: { Date(timeIntervalSince1970: 1_778_400_000) }
    )

    let project = try store.prepareStarterProject(policyContract: .simpleFeedForward(
        observationDimension: 8,
        actionDimension: 1,
        actionEncoding: .directMotor
    )) { checkpoint in
        try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
        try writeCheckpointFiles(at: checkpoint, policyContract: directMotorPolicy())
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
        let policy = directMotorPolicy()
        _ = try store.prepareStarterProject(policyContract: policy) { checkpoint in
            try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
            let url = checkpoint.appendingPathComponent(
                ManasMLXCheckpointFileLayout.current.requiredFiles(policyContract: policy)[0]
            )
            try Data("{}".utf8).write(to: url, options: .atomic)
        }
    }
}

@Test func learningStarterProjectStoreAcceptsCTBRStarterWithoutReflexWeights() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-starter-ctbr-\(UUID().uuidString)", isDirectory: true)
    let store = LearningStarterProjectStore(
        projectRoot: root,
        now: { Date(timeIntervalSince1970: 1_778_400_000) }
    )
    let policy = LearningProjectPolicyContract.simpleFeedForward(
        observationDimension: 64,
        actionDimension: 4,
        actionEncoding: .ctbr
    )

    let project = try store.prepareStarterProject(policyContract: policy) { checkpoint in
        try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
        try writeCheckpointFiles(at: checkpoint, policyContract: policy)
    }

    #expect(store.checkpointIsComplete(at: project.sourceCheckpoint, policyContract: policy))
    #expect(!FileManager.default.fileExists(
        atPath: project.sourceCheckpoint
            .appendingPathComponent(ManasMLXCheckpointFileLayout.current.reflexWeightsFileName)
            .path
    ))
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

    let directMotorPolicy = LearningProjectPolicyContract.simpleFeedForward(
        observationDimension: 8,
        actionDimension: 1,
        actionEncoding: .directMotor
    )

    _ = try store.prepareStarterProject(policyContract: directMotorPolicy) { checkpoint in
        try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
        try writeCheckpointFiles(at: checkpoint, policyContract: directMotorPolicy, prefix: "first-")
    }

    let project = try store.prepareStarterProject(
        regenerateSourceCheckpoint: true,
        policyContract: directMotorPolicy
    ) { checkpoint in
        try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
        try writeCheckpointFiles(at: checkpoint, policyContract: directMotorPolicy, prefix: "second-")
    }

    let modelFileName = ManasMLXCheckpointFileLayout.current.modelManifestFileName
    let model = try String(
        contentsOf: project.sourceCheckpoint.appendingPathComponent(modelFileName),
        encoding: .utf8
    )
    #expect(model == "second-\(modelFileName)")
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

private func directMotorPolicy() -> LearningProjectPolicyContract {
    .simpleFeedForward(
        observationDimension: 8,
        actionDimension: 1,
        actionEncoding: .directMotor
    )
}

private func writeCheckpointFiles(
    at checkpoint: URL,
    policyContract: LearningProjectPolicyContract,
    prefix: String = ""
) throws {
    for fileName in ManasMLXCheckpointFileLayout.current.requiredFiles(policyContract: policyContract) {
        let url = checkpoint.appendingPathComponent(fileName)
        try Data("\(prefix)\(fileName)".utf8).write(to: url, options: .atomic)
    }
}
