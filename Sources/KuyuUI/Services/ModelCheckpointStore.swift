import Foundation
import KuyuMLX

struct RemovedModelArtifact: Sendable, Equatable {
    let url: URL
    let errorDescription: String?
}

struct ModelCheckpointStore {
    func rootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Kuyu", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    func modelDirectory(for id: UUID) -> URL {
        rootDirectory().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func loadPersistedModels() -> [TrainingModelInfo] {
        let root = rootDirectory()
        let fileManager = FileManager.default
        let directories: [URL]
        do {
            directories = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var models: [TrainingModelInfo] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for url in directories {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: [.isDirectoryKey])
            } catch {
                continue
            }
            guard values.isDirectory == true else { continue }
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            let manifestURL = url.appendingPathComponent("model.json")
            let data: Data
            do {
                data = try Data(contentsOf: manifestURL)
            } catch {
                continue
            }
            let manifest: ManasMLXModelManifest
            do {
                manifest = try decoder.decode(ManasMLXModelManifest.self, from: data)
            } catch {
                continue
            }

            let hasWeights = fileManager.fileExists(atPath: url.appendingPathComponent("core.safetensors").path)
            models.append(TrainingModelInfo(
                id: id,
                name: manifest.name,
                createdAt: manifest.createdAt,
                lastTrainedAt: manifest.lastTrainedAt,
                hasSupervisedBootstrap: hasWeights,
                storageURL: url
            ))
        }

        return models.sorted { $0.createdAt < $1.createdAt }
    }

    @MainActor
    func load(model: TrainingModelInfo, into store: ManasMLXModelStore) throws -> ManasMLXModelManifest? {
        let manifestURL = model.storageURL.appendingPathComponent("model.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
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

    func removeArtifacts(at url: URL) -> [RemovedModelArtifact] {
        let fileManager = FileManager.default
        let artifacts = [
            url.appendingPathComponent("core.safetensors"),
            url.appendingPathComponent("reflex.safetensors"),
            url.appendingPathComponent("model.json"),
        ]
        var removed: [RemovedModelArtifact] = []
        for artifact in artifacts where fileManager.fileExists(atPath: artifact.path) {
            do {
                try fileManager.removeItem(at: artifact)
                removed.append(RemovedModelArtifact(url: artifact, errorDescription: nil))
            } catch {
                removed.append(RemovedModelArtifact(url: artifact, errorDescription: "\(error)"))
            }
        }
        return removed
    }
}
