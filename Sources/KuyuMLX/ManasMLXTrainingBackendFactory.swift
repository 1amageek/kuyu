import Foundation
import KuyuCore
import KuyuScenarios
import KuyuTraining

@MainActor
public struct ManasMLXTrainingBackendBundle {
    public let backend: ManasMLXTrainingBackend
    public let sourceSnapshot: TrainingBackendSnapshot?

    public init(
        backend: ManasMLXTrainingBackend,
        sourceSnapshot: TrainingBackendSnapshot?
    ) {
        self.backend = backend
        self.sourceSnapshot = sourceSnapshot
    }
}

@MainActor
public struct ManasMLXTrainingBackendFactory {
    public init() {}

    public func makeWorkerLocalBackend(
        activeStore: ManasMLXModelStore,
        runID: String,
        runRequest: SimulationRunRequest,
        datasetRoot: URL
    ) -> ManasMLXTrainingBackendBundle {
        let sourceSnapshot = makeSourceSnapshotIfAvailable(
            activeStore: activeStore,
            runID: runID,
            runRequest: runRequest,
            datasetRoot: datasetRoot
        )
        let workerStore = ManasMLXModelStore()
        let workerRuntime = ManasMLXTrainingRuntime(modelStore: workerStore)
        let candidateCheckpointDirectory = datasetRoot
            .appendingPathComponent("candidate-checkpoints", isDirectory: true)
        return ManasMLXTrainingBackendBundle(
            backend: ManasMLXTrainingBackend(
                runtime: workerRuntime,
                saveDirectory: candidateCheckpointDirectory
            ),
            sourceSnapshot: sourceSnapshot
        )
    }

    private func makeSourceSnapshotIfAvailable(
        activeStore: ManasMLXModelStore,
        runID: String,
        runRequest: SimulationRunRequest,
        datasetRoot: URL
    ) -> TrainingBackendSnapshot? {
        let sourceDirectory = datasetRoot.appendingPathComponent("source-checkpoint", isDirectory: true)
        do {
            let manifest = try ManasMLXTrainingRuntime(modelStore: activeStore)
                .saveCandidateCheckpoint(to: sourceDirectory)
            return TrainingBackendSnapshot(
                snapshotID: "\(runID)-source",
                checkpointID: manifest.name,
                checkpointURL: sourceDirectory,
                descriptorID: runRequest.modelDescriptorPath,
                configHash: runRequest.modelDescriptorPath
            )
        } catch ModelStoreError.coreModelNotInitialized {
            return nil
        } catch {
            return nil
        }
    }
}
