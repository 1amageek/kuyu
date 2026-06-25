import Foundation
import KuyuMLX
import Testing
@testable import KuyuUI

@Test(.timeLimit(.minutes(1))) func modelCheckpointStoreLoadsPersistedModelsThroughMLXCatalog() throws {
    let store = ModelCheckpointStore()
    let id = UUID()
    let directory = store.modelDirectory(for: id)
    defer {
        removeModelCheckpointTestDirectory(directory)
    }

    try writeModelCheckpoint(
        directory,
        name: "catalog-owned",
        createdAt: Date(timeIntervalSince1970: 40),
        lastTrainedAt: Date(timeIntervalSince1970: 50),
        writeCoreWeights: true
    )

    let persistedModel = try #require(store.loadPersistedModels().first { $0.id == id })
    #expect(persistedModel.name == "catalog-owned")
    #expect(persistedModel.createdAt == Date(timeIntervalSince1970: 40))
    #expect(persistedModel.lastTrainedAt == Date(timeIntervalSince1970: 50))
    #expect(persistedModel.hasSupervisedBootstrap)
    #expect(persistedModel.storageURL == directory)
}

@Test(.timeLimit(.minutes(1))) func modelCheckpointStoreRemovesAllMLXCatalogArtifacts() throws {
    let store = ModelCheckpointStore()
    let directory = store.modelDirectory(for: UUID())
    defer {
        removeModelCheckpointTestDirectory(directory)
    }

    try writeModelCheckpoint(
        directory,
        name: "remove-catalog-owned",
        createdAt: Date(timeIntervalSince1970: 60),
        lastTrainedAt: nil,
        writeCoreWeights: true
    )
    let layout = ManasMLXCheckpointFileLayout.current
    try Data("reflex".utf8).write(
        to: directory.appendingPathComponent(layout.reflexWeightsFileName),
        options: .atomic
    )
    try Data("bundle".utf8).write(
        to: directory.appendingPathComponent(layout.bundleManifestFileName),
        options: .atomic
    )

    let removed = store.removeArtifacts(at: directory)

    #expect(removed.map { $0.url.lastPathComponent } == layout.removableArtifactFileNames)
    #expect(removed.allSatisfy { $0.errorDescription == nil })
    for fileName in layout.removableArtifactFileNames {
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path))
    }
}

private func writeModelCheckpoint(
    _ directory: URL,
    name: String,
    createdAt: Date,
    lastTrainedAt: Date?,
    writeCoreWeights: Bool
) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let manifest = TestModelManifest(
        name: name,
        createdAt: createdAt,
        lastTrainedAt: lastTrainedAt,
        coreConfig: TestCoreConfig(
            inputSize: 8,
            embeddingSize: 8,
            fastHiddenSize: 8,
            slowHiddenSize: 4,
            driveCount: 1,
            auxSize: 0
        ),
        reflexConfig: nil
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let layout = ManasMLXCheckpointFileLayout.current
    try encoder.encode(manifest).write(
        to: directory.appendingPathComponent(layout.modelManifestFileName),
        options: .atomic
    )
    if writeCoreWeights {
        try Data("core".utf8).write(
            to: directory.appendingPathComponent(layout.coreWeightsFileName),
            options: .atomic
        )
    }
}

private struct TestModelManifest: Encodable {
    let formatVersion = 1
    let name: String
    let createdAt: Date
    let lastTrainedAt: Date?
    let coreConfig: TestCoreConfig
    let reflexConfig: TestCoreConfig?

    init(
        name: String,
        createdAt: Date,
        lastTrainedAt: Date?,
        coreConfig: TestCoreConfig,
        reflexConfig: TestCoreConfig? = nil
    ) {
        self.name = name
        self.createdAt = createdAt
        self.lastTrainedAt = lastTrainedAt
        self.coreConfig = coreConfig
        self.reflexConfig = reflexConfig
    }
}

private struct TestCoreConfig: Encodable {
    let inputSize: Int
    let embeddingSize: Int
    let fastHiddenSize: Int
    let slowHiddenSize: Int
    let driveCount: Int
    let driveScale: Double = 1.0
    let auxSize: Int
    let auxEnabled: Bool = false
}

private func removeModelCheckpointTestDirectory(_ directory: URL) {
    guard FileManager.default.fileExists(atPath: directory.path) else {
        return
    }
    do {
        try FileManager.default.removeItem(at: directory)
    } catch {
        Issue.record("Failed to remove temporary model checkpoint directory \(directory.path): \(error)")
    }
}
