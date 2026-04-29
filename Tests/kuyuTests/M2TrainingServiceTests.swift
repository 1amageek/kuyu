import Foundation
import KuyuTraining
import KuyuScenarios
import KuyuWorldModel
import ManasMLXModels
import Testing
@testable import KuyuMLX

@Test(.timeLimit(.minutes(1))) func imagineTrainRequiresStateWorldModelManifestFields() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-m2-missing-state-fields-\(UUID().uuidString)", isDirectory: true)
    let worldModelDirectory = root.appendingPathComponent("world-model", isDirectory: true)
    let saveDirectory = root.appendingPathComponent("imagination", isDirectory: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary directory \(root.path): \(error)")
        }
    }

    try FileManager.default.createDirectory(at: worldModelDirectory, withIntermediateDirectories: true)
    let manifest = WorldModelTrainingManifest(
        datasetHash: "dataset",
        descriptorHash: "descriptor",
        lossConfigHash: "loss",
        modelId: "missing-state-fields",
        checkpointPath: worldModelDirectory.appendingPathComponent("world-model.safetensors").path,
        losses: [1.0],
        coreConfig: ManasMLXCoreConfig(
            inputSize: 4,
            embeddingSize: 8,
            fastHiddenSize: 8,
            slowHiddenSize: 4,
            driveCount: 2,
            auxSize: 4,
            stochasticCategories: 2,
            stochasticClasses: 2,
            rewardHeadHiddenSize: 4,
            continueHeadHiddenSize: 4,
            valueHeadHiddenSize: 4
        )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(
        to: worldModelDirectory.appendingPathComponent("world-model-manifest.json"),
        options: [.atomic]
    )

    do {
        _ = try M2TrainingService().imagineTrain(
            worldModelDirectory: worldModelDirectory,
            saveDirectory: saveDirectory,
            horizon: 1,
            epochs: 1
        )
        Issue.record("Expected missing StateWorldModel fields to fail closed")
    } catch let error as M2TrainingService.TrainingError {
        #expect(error == .missingRequiredStateWorldModel(worldModelDirectory.appendingPathComponent("world-model-manifest.json")))
    }
}

@Test(.timeLimit(.minutes(1))) func m2TrainingServiceRejectsInvalidPublicArguments() throws {
    let service = M2TrainingService()
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-m2-invalid-args-\(UUID().uuidString)", isDirectory: true)
    defer {
        do {
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        } catch {
            Issue.record("Failed to remove temporary directory \(root.path): \(error)")
        }
    }

    do {
        _ = try service.trainWorldModel(
            datasetDirectory: root,
            saveDirectory: root,
            sequenceLength: 0,
            epochs: 1,
            learningRate: 0.001,
            maxBatches: nil
        )
        Issue.record("Expected invalid sequence length to fail")
    } catch let error as M2TrainingService.TrainingError {
        #expect(error == .invalidSequenceLength(0))
    }

    do {
        _ = try service.imagineTrain(
            worldModelDirectory: root,
            saveDirectory: root,
            horizon: 0,
            epochs: 1
        )
        Issue.record("Expected invalid horizon to fail")
    } catch let error as M2TrainingService.TrainingError {
        #expect(error == .invalidHorizon(0))
    }
}

@Test(.timeLimit(.minutes(1))) func worldModelManifestDecodesLegacyPayloadWithoutDatasetPath() throws {
    let encoded = try JSONEncoder().encode(WorldModelTrainingManifest(
        datasetHash: "dataset",
        descriptorHash: "descriptor",
        lossConfigHash: "loss",
        modelId: "legacy",
        checkpointPath: "/tmp/world-model.safetensors",
        losses: [1.0],
        coreConfig: ManasMLXCoreConfig(
            inputSize: 4,
            embeddingSize: 8,
            fastHiddenSize: 8,
            slowHiddenSize: 4,
            driveCount: 2,
            auxSize: 4,
            stochasticCategories: 2,
            stochasticClasses: 2,
            rewardHeadHiddenSize: 4,
            continueHeadHiddenSize: 4,
            valueHeadHiddenSize: 4
        )
    ))
    let manifest = try JSONDecoder().decode(
        WorldModelTrainingManifest.self,
        from: encoded
    )

    #expect(manifest.datasetPath == nil)
    #expect(manifest.modelId == "legacy")
}

@Test(.timeLimit(.minutes(1))) func trainWorldModelFailsClosedForMixedActionDimensions() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-m2-mixed-actions-\(UUID().uuidString)", isDirectory: true)
    let saveDirectory = root.appendingPathComponent("model", isDirectory: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary directory \(root.path): \(error)")
        }
    }

    try writeDataset(
        root.appendingPathComponent("episode-a", isDirectory: true),
        scenarioId: "mixed-a",
        actionValues: [0.1, 0.2]
    )
    try writeDataset(
        root.appendingPathComponent("episode-b", isDirectory: true),
        scenarioId: "mixed-b",
        actionValues: [0.1, 0.2, 0.3]
    )

    do {
        _ = try M2TrainingService().trainWorldModel(
            datasetDirectory: root,
            saveDirectory: saveDirectory,
            sequenceLength: 1,
            epochs: 1,
            learningRate: 0.001,
            maxBatches: 1
        )
        Issue.record("Expected mixed action dimensions to fail closed")
    } catch let error as M2TrainingService.TrainingError {
        #expect(error == .inconsistentStateWorldModelActionDimensions([2, 3]))
    }
}

@Test(.timeLimit(.minutes(1))) func imagineTrainFailsClosedWhenStateWorldModelCheckpointIsMissing() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-m2-missing-state-world-model-\(UUID().uuidString)", isDirectory: true)
    let worldModelDirectory = root.appendingPathComponent("world-model", isDirectory: true)
    let saveDirectory = root.appendingPathComponent("imagination", isDirectory: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary directory \(root.path): \(error)")
        }
    }

    try FileManager.default.createDirectory(at: worldModelDirectory, withIntermediateDirectories: true)
    let coreCheckpoint = worldModelDirectory.appendingPathComponent("world-model.safetensors")
    let missingStateCheckpoint = worldModelDirectory.appendingPathComponent("state-world-model.safetensors")
    let manifest = WorldModelTrainingManifest(
        datasetHash: "dataset",
        descriptorHash: "descriptor",
        lossConfigHash: "loss",
        modelId: "missing-state-checkpoint",
        checkpointPath: coreCheckpoint.path,
        stateWorldModelCheckpointPath: missingStateCheckpoint.path,
        losses: [1.0],
        stateWorldModelLosses: [1.0],
        coreConfig: ManasMLXCoreConfig(
            inputSize: 4,
            embeddingSize: 8,
            fastHiddenSize: 8,
            slowHiddenSize: 4,
            driveCount: 2,
            auxSize: 4,
            stochasticCategories: 2,
            stochasticClasses: 2,
            rewardHeadHiddenSize: 4,
            continueHeadHiddenSize: 4,
            valueHeadHiddenSize: 4
        ),
        stateWorldModelConfig: WorldModelConfig(
            physicsDimensions: 13,
            sensorDimensions: 6,
            actionDimensions: 4,
            hiddenDimensions: 8,
            stochasticCategories: 2,
            stochasticClasses: 2,
            residualDimensions: 13,
            extensionDimensions: 1,
            tokenizerLayers: 1,
            physicsEmbedDimensions: 8
        )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(
        to: worldModelDirectory.appendingPathComponent("world-model-manifest.json"),
        options: [.atomic]
    )

    do {
        _ = try M2TrainingService().imagineTrain(
            worldModelDirectory: worldModelDirectory,
            saveDirectory: saveDirectory,
            horizon: 1,
            epochs: 1
        )
        Issue.record("Expected missing state world-model checkpoint to fail closed")
    } catch let error as M2TrainingService.TrainingError {
        #expect(error == .missingStateWorldModelCheckpoint(missingStateCheckpoint))
    }
}

@Test(.timeLimit(.minutes(1))) func manasMLXRolloutPolicyFactoryFailsClosedWhenSnapshotWeightsAreMissing() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-m2-missing-snapshot-\(UUID().uuidString)", isDirectory: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary directory \(root.path): \(error)")
        }
    }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let manifest = ManasMLXModelManifest(
        name: "missing-snapshot",
        createdAt: Date(timeIntervalSince1970: 0),
        lastTrainedAt: nil,
        coreConfig: ManasMLXCoreConfig(
            inputSize: 16,
            embeddingSize: 8,
            fastHiddenSize: 8,
            slowHiddenSize: 4,
            driveCount: 4,
            auxSize: 4
        ),
        reflexConfig: ManasMLXReflexConfig(inputSize: 6, driveCount: 4)
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: root.appendingPathComponent("model.json"), options: [.atomic])

    let factory = ManasMLXRolloutPolicyFactory(snapshotDirectory: root)
    let definition = try KuyAtt1Suite().scenarios()[0]
    do {
        _ = try factory.makePolicy(
            definition: definition,
            workerIndex: 0
        )
        Issue.record("Expected missing snapshot checkpoint to fail closed")
    } catch let error as ManasMLXRolloutPolicyFactory.FactoryError {
        #expect(error == .missingCoreCheckpoint(root.appendingPathComponent("core.safetensors")))
    }
}

private func writeDataset(
    _ directory: URL,
    scenarioId: String,
    actionValues: [Double]
) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let metadata = TrainingDatasetMetadata(
        scenarioId: scenarioId,
        seed: 1,
        timeStep: 0.001,
        determinismTier: "tier1",
        configHash: scenarioId,
        channelCount: 1,
        driveCount: actionValues.count,
        recordCount: 2
    )
    let records = [
        TrainingDatasetRecord(
            time: 0.0,
            sensors: [TrainingSensorSample(channelIndex: 0, value: 0.0, timestamp: 0.0)],
            driveIntents: [],
            reflexCorrections: [],
            physicsState: rootState(z: 1.0),
            actualState: rootState(z: 1.0),
            actionValues: actionValues,
            continueValue: 1.0,
            reward: 0.0,
            done: false,
            truncated: false,
            episodeId: scenarioId,
            policyId: "test"
        ),
        TrainingDatasetRecord(
            time: 0.001,
            sensors: [TrainingSensorSample(channelIndex: 0, value: 0.0, timestamp: 0.001)],
            driveIntents: [],
            reflexCorrections: [],
            physicsState: rootState(z: 1.0),
            actualState: rootState(z: 1.01),
            actionValues: actionValues,
            continueValue: 0.0,
            reward: 0.0,
            done: false,
            truncated: true,
            episodeId: scenarioId,
            policyId: "test"
        ),
    ]
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(metadata).write(
        to: directory.appendingPathComponent("meta.json"),
        options: [.atomic]
    )
    let recordEncoder = JSONEncoder()
    recordEncoder.outputFormatting = [.withoutEscapingSlashes]
    let encodedLines = try records.map { record in
        let data = try recordEncoder.encode(record)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    let body = encodedLines.joined(separator: "\n") + "\n"
    try body.write(
        to: directory.appendingPathComponent("records.jsonl"),
        atomically: true,
        encoding: .utf8
    )
}

private func rootState(z: Double) -> [Double] {
    [
        0.0, 0.0, z,
        0.0, 0.0, 0.0,
        1.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
    ]
}
