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

    @MainActor
    func load(model: TrainingModelInfo, into store: ManasMLXModelStore) throws -> ManasMLXModelManifest? {
        guard catalog.manifestExists(at: model.storageURL) else { return nil }
        return try store.loadModel(from: model.storageURL)
    }

    @MainActor
    func persist(model: TrainingModelInfo, from store: ManasMLXModelStore) throws {
        try store.saveModel(
            to: model.storageURL,
            name: model.name,
            createdAt: model.createdAt,
            lastTrainedAt: model.lastTrainedAt
        )
    }

    func removeArtifacts(at url: URL) -> [ManasMLXRemovedModelCheckpointArtifact] {
        catalog.removeArtifacts(at: url)
    }
}
