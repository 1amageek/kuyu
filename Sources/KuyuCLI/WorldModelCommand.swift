import ArgumentParser
import Foundation
import KuyuMLX

struct TrainWorldModel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "train-world-model",
        abstract: "Train a Manas world model from a Kuyu rollout dataset."
    )

    @Option(help: "Dataset directory containing meta.json and records.jsonl.")
    var dataset: String

    @Option(name: .customLong("save-model"), help: "Directory to save the world-model checkpoint and manifest.")
    var saveModelPath: String

    @Option(name: .customLong("sequence"), help: "Sequence length for world-model training.")
    var sequenceLength: Int = 8

    @Option(name: .customLong("epochs"), help: "Training epochs.")
    var epochs: Int = 1

    @Option(name: .customLong("lr"), help: "Learning rate.")
    var learningRate: Double = 0.001

    @Option(name: .customLong("max-batches"), help: "Maximum batches for smoke training.")
    var maxBatches: Int?

    mutating func run() async throws {
        try MLXRuntimeReadinessService().check()
        guard sequenceLength > 0 else {
            throw ValidationError("--sequence must be greater than 0.")
        }
        guard epochs > 0 else {
            throw ValidationError("--epochs must be greater than 0.")
        }
        guard learningRate.isFinite && learningRate > 0 else {
            throw ValidationError("--lr must be finite and greater than 0.")
        }
        let manifest = try M2TrainingService().trainWorldModel(
            datasetDirectory: URL(fileURLWithPath: dataset, isDirectory: true),
            saveDirectory: URL(fileURLWithPath: saveModelPath, isDirectory: true),
            sequenceLength: sequenceLength,
            epochs: epochs,
            learningRate: Float(learningRate),
            maxBatches: maxBatches
        )
        print("[world-model] saved checkpoint=\(manifest.checkpointPath) losses=\(manifest.losses)")
        if let stateCheckpoint = manifest.stateWorldModelCheckpointPath {
            print("[world-model] saved stateCheckpoint=\(stateCheckpoint) stateLosses=\(manifest.stateWorldModelLosses ?? [])")
        } else {
            print("[world-model] stateCheckpoint=none reason=dataset-missing-m2-state-fields")
        }
    }
}

struct ImagineTrain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "imagine-train",
        abstract: "Run a smoke imagination-training pass from a world-model manifest."
    )

    @Option(name: .customLong("world-model"), help: "World-model directory containing world-model-manifest.json.")
    var worldModelPath: String

    @Option(name: .customLong("save-model"), help: "Directory to save imagination-training checkpoint and manifest.")
    var saveModelPath: String

    @Option(help: "Imagination horizon.")
    var horizon: Int = 4

    @Option(help: "Training epochs.")
    var epochs: Int = 1

    @Option(name: .customLong("fused-evidence-output"), help: "Optional output directory for fused-environment-long-horizon-artifact.json after accepted imagination training.")
    var fusedEvidenceOutputPath: String?

    @Option(help: "Dataset directory containing meta.json and records.jsonl for fused evidence. Defaults to the world-model manifest datasetPath.")
    var dataset: String?

    @Option(name: .customLong("dataset-index"), help: "Dataset index when the dataset root contains multiple dataset directories.")
    var datasetIndex: Int = 0

    @Option(name: .customLong("start-record"), help: "First dataset record index to replay for fused evidence.")
    var startRecordIndex: Int = 0

    @Option(name: .customLong("fused-horizon"), help: "Optional fused evidence horizon. Defaults to the accepted imagination artifact horizon.")
    var fusedHorizon: Int?

    @Option(name: .customLong("time-step"), help: "Optional fused evidence timestep override. Must match the dataset timestep.")
    var timeStep: Double?

    mutating func run() async throws {
        try MLXRuntimeReadinessService().check()
        guard horizon > 0 else {
            throw ValidationError("--horizon must be greater than 0.")
        }
        guard epochs > 0 else {
            throw ValidationError("--epochs must be greater than 0.")
        }
        if fusedEvidenceOutputPath == nil && (
            dataset != nil ||
                datasetIndex != 0 ||
                startRecordIndex != 0 ||
                fusedHorizon != nil ||
                timeStep != nil
        ) {
            throw ValidationError("Specify --fused-evidence-output when configuring fused evidence publication.")
        }
        let service = M2TrainingService()
        let manifest: ImaginationTrainingManifest
        if let fusedEvidenceOutputPath {
            let request = try M2ImaginationFusedEvidenceRequest(
                worldModelDirectory: URL(fileURLWithPath: worldModelPath, isDirectory: true),
                saveDirectory: URL(fileURLWithPath: saveModelPath, isDirectory: true),
                fusedEvidenceOutputDirectory: URL(fileURLWithPath: fusedEvidenceOutputPath, isDirectory: true),
                datasetDirectory: dataset.map { URL(fileURLWithPath: $0, isDirectory: true) },
                datasetIndex: datasetIndex,
                startRecordIndex: startRecordIndex,
                horizon: horizon,
                epochs: epochs,
                fusedEvidenceHorizon: fusedHorizon,
                timeStep: timeStep
            )
            let result = try service.publishFusedEvidenceFromImaginationTraining(request)
            manifest = result.imaginationManifest
            print("[world-model-fused-evidence] manifest=\(result.imaginationManifestURL.path)")
            print("[world-model-fused-evidence] physicsGroundedArtifact=\(result.physicsGroundedImaginationArtifactURL.path)")
            print("[world-model-fused-evidence] artifact=\(result.fusedEvidenceArtifactURL.path)")
            print("[world-model-fused-evidence] projectEvidence=\(result.projectEvidencePublication.projectEvidencePackURL.path)")
            print("[world-model-fused-evidence] projectID=\(result.projectEvidencePublication.projectEvidencePack.projectID)")
            print("[world-model-fused-evidence] modelId=\(result.fusedEvidence.modelId) horizon=\(result.fusedEvidence.horizon) timeStep=\(result.fusedEvidence.timeStep)")
            print("[world-model-fused-evidence] maxResidualAbs=\(result.fusedEvidence.maxResidualAbs) maxUncertainty=\(result.fusedEvidence.maxUncertainty)")
        } else {
            manifest = try service.imagineTrain(
                worldModelDirectory: URL(fileURLWithPath: worldModelPath, isDirectory: true),
                saveDirectory: URL(fileURLWithPath: saveModelPath, isDirectory: true),
                horizon: horizon,
                epochs: epochs
            )
        }
        print("[imagination] saved rollback=\(manifest.rollbackCheckpointPath) accepted=\(manifest.validationAccepted)")
        if let stateCheckpoint = manifest.stateWorldModelCheckpointPath {
            print("[imagination] validated stateCheckpoint=\(stateCheckpoint) reason=\(manifest.validationReason ?? "accepted")")
        }
    }
}

struct PublishWorldModelFusedEvidence: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish-world-model-fused-evidence",
        abstract: "Publish fused long-horizon evidence from an accepted imagination manifest and Kuyu dataset."
    )

    @Option(name: .customLong("imagination"), help: "Accepted imagination-training directory containing imagination-training-manifest.json.")
    var imaginationPath: String

    @Option(help: "Dataset directory containing meta.json and records.jsonl. Defaults to the world-model manifest datasetPath.")
    var dataset: String?

    @Option(name: .customLong("reference-directory"), help: "Additional directory allowed for saved artifact references.")
    var referenceDirectories: [String] = []

    @Option(help: "Output directory for fused-environment-long-horizon-artifact.json.")
    var output: String

    @Option(name: .customLong("dataset-index"), help: "Dataset index when the dataset root contains multiple dataset directories.")
    var datasetIndex: Int = 0

    @Option(name: .customLong("start-record"), help: "First dataset record index to replay.")
    var startRecordIndex: Int = 0

    @Option(help: "Optional publication horizon. Defaults to the physics-grounded imagination artifact horizon.")
    var horizon: Int?

    @Option(name: .customLong("time-step"), help: "Optional timestep override. Must match the dataset timestep.")
    var timeStep: Double?

    mutating func run() async throws {
        try MLXRuntimeReadinessService().check()
        let outputDirectory = URL(fileURLWithPath: output, isDirectory: true)
        let request = try DatasetBackedFusedLongHorizonPublicationRequest(
            source: .imaginationTrainingManifestRoot(
                URL(fileURLWithPath: imaginationPath, isDirectory: true)
            ),
            datasetDirectory: dataset.map { URL(fileURLWithPath: $0, isDirectory: true) },
            referenceDirectories: referenceDirectories.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            },
            outputDirectory: outputDirectory,
            datasetIndex: datasetIndex,
            startRecordIndex: startRecordIndex,
            horizon: horizon,
            timeStep: timeStep
        )
        let publication = try DatasetBackedFusedLongHorizonEvidenceService().publication(request: request)
        let artifact = publication.artifact
        print("[world-model-fused-evidence] physicsGroundedArtifact=\(publication.physicsGroundedImaginationArtifactURL.path)")
        print("[world-model-fused-evidence] artifact=\(publication.artifactURL.path)")
        print("[world-model-fused-evidence] modelId=\(artifact.modelId) horizon=\(artifact.horizon) timeStep=\(artifact.timeStep)")
        print("[world-model-fused-evidence] maxResidualAbs=\(artifact.maxResidualAbs) maxUncertainty=\(artifact.maxUncertainty)")
    }
}
