import Foundation
import KuyuMLX

struct ModelCheckpointStore {
    private let catalog = ManasMLXModelCheckpointCatalog()
    private let rootDirectoryOverride: URL?

    init(rootDirectory: URL? = nil) {
        self.rootDirectoryOverride = rootDirectory
    }

    func rootDirectory() -> URL {
        if let rootDirectoryOverride {
            return rootDirectoryOverride
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Kuyu", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    func modelDirectory(for id: UUID) -> URL {
        rootDirectory().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func loadPersistedModels() -> [TrainingModelInfo] {
        catalog.loadPersistedCheckpoints(from: rootDirectory()).map { checkpoint in
            TrainingModelInfo(
                id: checkpoint.id,
                name: checkpoint.name,
                createdAt: checkpoint.createdAt,
                lastTrainedAt: checkpoint.lastTrainedAt,
                hasSupervisedBootstrap: checkpoint.hasCoreWeights,
                storageURL: checkpoint.directory
            )
        }
    }

    func load(
        model: TrainingModelInfo,
        into store: ManasMLXModelStore
    ) async throws -> ManasMLXModelManifest? {
        guard catalog.manifestExists(at: model.storageURL) else { return nil }
        return try await store.loadModel(from: model.storageURL)
    }

    func removeArtifacts(at url: URL) -> [ManasMLXRemovedModelCheckpointArtifact] {
        catalog.removeArtifacts(at: url)
    }
}
