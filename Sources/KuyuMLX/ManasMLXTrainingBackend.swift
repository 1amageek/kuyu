import Foundation
import KuyuTraining

@MainActor
public struct ManasMLXTrainingBackend: SnapshotTrainingBackend {
    public enum SnapshotError: Error, Sendable, Equatable {
        case missingSaveDirectory
    }

    private let runtime: ManasMLXTrainingRuntime
    private let saveDirectory: URL?

    public init(
        runtime: ManasMLXTrainingRuntime,
        saveDirectory: URL? = nil
    ) {
        self.runtime = runtime
        self.saveDirectory = saveDirectory
    }

    public func trainSupervised(request: TrainingBackendRequest) async throws -> TrainingBackendResult {
        let result = try await runtime.trainSupervised(request: request)

        var checkpointID: String?
        var checkpointURL: URL?
        if let checkpointDirectory = checkpointDirectory(for: request) {
            let manifest = try runtime.saveCandidateCheckpoint(to: checkpointDirectory)
            checkpointID = manifest.name
            checkpointURL = checkpointDirectory
        }

        return TrainingBackendResult(
            finalLoss: result.finalLoss,
            epochs: result.epochs,
            candidateCheckpointID: checkpointID,
            candidateCheckpointURL: checkpointURL
        )
    }

    private func checkpointDirectory(for request: TrainingBackendRequest) -> URL? {
        guard let saveDirectory else { return nil }
        let iterationName = request.datasetURL.lastPathComponent.isEmpty
            ? UUID().uuidString
            : request.datasetURL.lastPathComponent
        return saveDirectory.appendingPathComponent(iterationName, isDirectory: true)
    }

    public func makeSnapshot(for manifest: LearningRunManifest) async throws -> TrainingBackendSnapshot {
        guard let saveDirectory else {
            throw SnapshotError.missingSaveDirectory
        }
        let modelManifest = try runtime.saveCandidateCheckpoint(to: saveDirectory)
        return TrainingBackendSnapshot(
            snapshotID: "\(manifest.runID)-\(UUID().uuidString)",
            checkpointID: modelManifest.name,
            checkpointURL: saveDirectory,
            descriptorID: manifest.descriptorID,
            configHash: manifest.configHash
        )
    }
}
