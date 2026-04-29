import Foundation
import KuyuCore
import KuyuTraining
import KuyuWorldModel
import ManasCore
import ManasMLXModels
import ManasMLXTraining
import ManasTrainingData
import MLX
import MLXNN

public struct WorldModelTrainingManifest: Sendable, Codable, Equatable {
    public let datasetHash: String
    public let datasetPath: String?
    public let descriptorHash: String
    public let lossConfigHash: String
    public let modelId: String
    public let checkpointPath: String
    public let stateWorldModelCheckpointPath: String?
    public let losses: [Float]
    public let stateWorldModelLosses: [Float]?
    public let coreConfig: ManasMLXCoreConfig
    public let stateWorldModelConfig: WorldModelConfig?

    public init(
        datasetHash: String,
        datasetPath: String? = nil,
        descriptorHash: String,
        lossConfigHash: String,
        modelId: String,
        checkpointPath: String,
        stateWorldModelCheckpointPath: String? = nil,
        losses: [Float],
        stateWorldModelLosses: [Float]? = nil,
        coreConfig: ManasMLXCoreConfig,
        stateWorldModelConfig: WorldModelConfig? = nil
    ) {
        self.datasetHash = datasetHash
        self.datasetPath = datasetPath
        self.descriptorHash = descriptorHash
        self.lossConfigHash = lossConfigHash
        self.modelId = modelId
        self.checkpointPath = checkpointPath
        self.stateWorldModelCheckpointPath = stateWorldModelCheckpointPath
        self.losses = losses
        self.stateWorldModelLosses = stateWorldModelLosses
        self.coreConfig = coreConfig
        self.stateWorldModelConfig = stateWorldModelConfig
    }
}

public struct ImaginationTrainingManifest: Sendable, Codable, Equatable {
    public let worldModelCheckpointPath: String
    public let stateWorldModelCheckpointPath: String?
    public let rollbackCheckpointPath: String
    public let modelId: String
    public let actorLosses: [Float]
    public let criticLosses: [Float]
    public let validationAccepted: Bool
    public let validationReason: String?

    public init(
        worldModelCheckpointPath: String,
        stateWorldModelCheckpointPath: String? = nil,
        rollbackCheckpointPath: String,
        modelId: String,
        actorLosses: [Float],
        criticLosses: [Float],
        validationAccepted: Bool,
        validationReason: String? = nil
    ) {
        self.worldModelCheckpointPath = worldModelCheckpointPath
        self.stateWorldModelCheckpointPath = stateWorldModelCheckpointPath
        self.rollbackCheckpointPath = rollbackCheckpointPath
        self.modelId = modelId
        self.actorLosses = actorLosses
        self.criticLosses = criticLosses
        self.validationAccepted = validationAccepted
        self.validationReason = validationReason
    }
}

public struct M2TrainingService: Sendable {
    public enum TrainingError: Error, Equatable {
        case emptyDataset(URL)
        case emptyWorldModelBatches
        case noTrainingDatasetsFound(URL)
        case incompatibleDatasetShape(URL, expectedChannels: Int, actualChannels: Int, expectedDrives: Int, actualDrives: Int)
        case missingWorldModelManifest(URL)
        case missingWorldModelCheckpoint(URL)
        case validationRejected(String)
        case missingStateWorldModelFields(URL)
        case invalidStateWorldModelDimensions(URL, expected: Int, actual: Int)
        case missingStateWorldModelCheckpoint(URL)
        case missingStateWorldModelConfig(URL)
        case missingRequiredStateWorldModel(URL)
        case inconsistentStateWorldModelActionDimensions([Int])
        case invalidSequenceLength(Int)
        case invalidEpochs(Int)
        case invalidLearningRate(Float)
        case invalidHorizon(Int)
        case invalidMaxBatches(Int)
    }

    public init() {}

    public func trainWorldModel(
        datasetDirectory: URL,
        saveDirectory: URL,
        sequenceLength: Int,
        epochs: Int,
        learningRate: Float,
        maxBatches: Int?
    ) throws -> WorldModelTrainingManifest {
        try validateTrainingArguments(
            sequenceLength: sequenceLength,
            epochs: epochs,
            learningRate: learningRate,
            maxBatches: maxBatches
        )
        try validateStateWorldModelDatasetIfPresent(datasetDirectory)
        let datasets = try loadTrainingDatasets(from: datasetDirectory)
        let first = datasets[0]
        try validateDatasetShapes(datasets, expected: first.metadata)
        guard datasets.contains(where: { !$0.records.isEmpty }) else {
            throw TrainingError.emptyDataset(datasetDirectory)
        }

        var batches: [ManasMLXWorldModelBatch] = []
        var remainingBatches = maxBatches
        for dataset in datasets where !dataset.records.isEmpty {
            var pipeline = ManasTrunkPipeline(
                bundle: PassThroughNerveBundle(configuration: .init(channelCount: dataset.metadata.channelCount)),
                gate: IdentityGating(),
                trunks: SpikeTrunksBuilder(configuration: .init(spikeGain: 1.0))
            )
            let builder = ManasTrainingBatchBuilder(
                sequenceLength: sequenceLength,
                driveCount: dataset.metadata.driveCount,
                maxBatches: remainingBatches
            )
            let datasetBatches = try builder.makeWorldModelBatches(dataset: dataset, pipeline: &pipeline)
            batches.append(contentsOf: datasetBatches)
            if let remainingBatchesValue = remainingBatches {
                remainingBatches = max(remainingBatchesValue - datasetBatches.count, 0)
                if remainingBatches == 0 { break }
            }
        }
        guard !batches.isEmpty else { throw TrainingError.emptyWorldModelBatches }

        let inputSize = max(first.metadata.channelCount * 4, 1)
        let config = ManasMLXCoreConfig(
            inputSize: inputSize,
            embeddingSize: 32,
            fastHiddenSize: 32,
            slowHiddenSize: 16,
            driveCount: first.metadata.driveCount,
            auxSize: inputSize,
            stochasticCategories: 4,
            stochasticClasses: 4,
            rewardHeadHiddenSize: 16,
            continueHeadHiddenSize: 16,
            valueHeadHiddenSize: 16
        )
        let model = ManasMLXCore(config: config)
        let lossConfig = WorldModelLoss.Config(stochasticCategories: 4, stochasticClasses: 4)
        let losses = WorldModelTrainer.train(
            model: model,
            batches: batches,
            lossConfig: lossConfig,
            learningRate: learningRate,
            epochs: epochs
        )
        let stateTraining = try trainStateWorldModelIfAvailable(
            datasetDirectory: datasetDirectory,
            saveDirectory: saveDirectory,
            sequenceLength: sequenceLength,
            epochs: epochs,
            learningRate: learningRate,
            maxBatches: maxBatches
        )

        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        let checkpointURL = saveDirectory.appendingPathComponent("world-model.safetensors")
        let arrays = Dictionary(model.parameters().flattened(), uniquingKeysWith: { first, _ in first })
        try MLX.save(arrays: arrays, url: checkpointURL)

        let datasetHash = try KuyuCore.ConfigHash.hash(DatasetCollectionDescriptor(datasets: datasets))
        let lossConfigHash = try KuyuCore.ConfigHash.hash(lossConfig)
        let manifest = WorldModelTrainingManifest(
            datasetHash: datasetHash,
            datasetPath: datasetDirectory.path,
            descriptorHash: descriptorHash(datasets),
            lossConfigHash: lossConfigHash,
            modelId: "manas-world-model-\(UUID().uuidString)",
            checkpointPath: checkpointURL.path,
            stateWorldModelCheckpointPath: stateTraining?.checkpointURL.path,
            losses: losses,
            stateWorldModelLosses: stateTraining?.losses,
            coreConfig: config,
            stateWorldModelConfig: stateTraining?.config
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: saveDirectory.appendingPathComponent("world-model-manifest.json"),
            options: [.atomic]
        )
        return manifest
    }

    public func imagineTrain(
        worldModelDirectory: URL,
        saveDirectory: URL,
        horizon: Int,
        epochs: Int
    ) throws -> ImaginationTrainingManifest {
        guard horizon > 0 else { throw TrainingError.invalidHorizon(horizon) }
        guard epochs > 0 else { throw TrainingError.invalidEpochs(epochs) }
        let manifestURL = worldModelDirectory.appendingPathComponent("world-model-manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw TrainingError.missingWorldModelManifest(manifestURL)
        }
        let manifest = try JSONDecoder().decode(
            WorldModelTrainingManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let stateValidation = try validateStateWorldModelIfPresent(
            manifest: manifest,
            directory: worldModelDirectory
        )
        let checkpointURL = try resolveWorldModelCheckpoint(manifest: manifest, directory: worldModelDirectory)
        let model = ManasMLXCore(config: manifest.coreConfig)
        let checkpointArrays = try MLX.loadArrays(url: checkpointURL)
        model.update(parameters: ModuleParameters.unflattened(checkpointArrays))

        let rollbackURL = saveDirectory.appendingPathComponent("rollback.safetensors")
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        let rollbackArrays = Dictionary(model.parameters().flattened(), uniquingKeysWith: { first, _ in first })
        try MLX.save(arrays: rollbackArrays, url: rollbackURL)

        let batchSize = 1
        let z = MLXArray.zeros([batchSize, manifest.coreConfig.stochasticLatentSize])
        let startState = ManasMLXCoreState(
            fast: MLXArray.zeros([batchSize, manifest.coreConfig.fastHiddenSize]),
            slow: MLXArray.zeros([batchSize, manifest.coreConfig.slowHiddenSize]),
            z: z
        )
        let result = ImaginationTrainer.train(
            model: model,
            startStates: [startState],
            config: ImaginationTrainer.Config(horizon: horizon),
            epochs: epochs
        )
        guard !result.actorLosses.contains(where: { !$0.isFinite })
                && !result.criticLosses.contains(where: { !$0.isFinite }) else {
            throw TrainingError.validationRejected("non-finite imagination loss")
        }

        let outputCheckpointURL = saveDirectory.appendingPathComponent("imagination-core-reflex.safetensors")
        let arrays = Dictionary(model.parameters().flattened(), uniquingKeysWith: { first, _ in first })
        try MLX.save(arrays: arrays, url: outputCheckpointURL)
        let output = ImaginationTrainingManifest(
            worldModelCheckpointPath: manifest.checkpointPath,
            stateWorldModelCheckpointPath: stateValidation?.checkpointURL.path,
            rollbackCheckpointPath: rollbackURL.path,
            modelId: "manas-imagination-\(UUID().uuidString)",
            actorLosses: result.actorLosses,
            criticLosses: result.criticLosses,
            validationAccepted: true,
            validationReason: stateValidation?.reason
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(output).write(
            to: saveDirectory.appendingPathComponent("imagination-training-manifest.json"),
            options: [.atomic]
        )
        return output
    }

    private func loadTrainingDatasets(from root: URL) throws -> [ManasTrainingDataset] {
        let fileManager = FileManager.default
        let metaURL = root.appendingPathComponent("meta.json")
        let recordsURL = root.appendingPathComponent("records.jsonl")

        if fileManager.fileExists(atPath: metaURL.path) && fileManager.fileExists(atPath: recordsURL.path) {
            return [try ManasTrainingDataset.load(from: root)]
        }

        let items = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        let sortedItems = items.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var datasets: [ManasTrainingDataset] = []
        for url in sortedItems {
            let meta = url.appendingPathComponent("meta.json")
            let records = url.appendingPathComponent("records.jsonl")
            guard fileManager.fileExists(atPath: meta.path),
                  fileManager.fileExists(atPath: records.path) else {
                continue
            }
            datasets.append(try ManasTrainingDataset.load(from: url))
        }
        guard !datasets.isEmpty else {
            throw TrainingError.noTrainingDatasetsFound(root)
        }
        return datasets
    }

    private func validateTrainingArguments(
        sequenceLength: Int,
        epochs: Int,
        learningRate: Float,
        maxBatches: Int?
    ) throws {
        guard sequenceLength > 0 else { throw TrainingError.invalidSequenceLength(sequenceLength) }
        guard epochs > 0 else { throw TrainingError.invalidEpochs(epochs) }
        guard learningRate.isFinite && learningRate > 0 else {
            throw TrainingError.invalidLearningRate(learningRate)
        }
        if let maxBatches, maxBatches <= 0 {
            throw TrainingError.invalidMaxBatches(maxBatches)
        }
    }

    private func validateDatasetShapes(
        _ datasets: [ManasTrainingDataset],
        expected: ManasTrainingDatasetMetadata
    ) throws {
        for dataset in datasets {
            guard dataset.metadata.channelCount == expected.channelCount,
                  dataset.metadata.driveCount == expected.driveCount else {
                throw TrainingError.incompatibleDatasetShape(
                    URL(fileURLWithPath: dataset.metadata.scenarioId),
                    expectedChannels: expected.channelCount,
                    actualChannels: dataset.metadata.channelCount,
                    expectedDrives: expected.driveCount,
                    actualDrives: dataset.metadata.driveCount
                )
            }
        }
    }

    private func descriptorHash(_ datasets: [ManasTrainingDataset]) -> String {
        datasets
            .map(\.metadata.configHash)
            .sorted()
            .joined(separator: "+")
    }

    private func resolveWorldModelCheckpoint(
        manifest: WorldModelTrainingManifest,
        directory: URL
    ) throws -> URL {
        let manifestURL = URL(fileURLWithPath: manifest.checkpointPath)
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            return manifestURL
        }

        let localURL = directory.appendingPathComponent("world-model.safetensors")
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        throw TrainingError.missingWorldModelCheckpoint(manifestURL)
    }

    private func validateStateWorldModelIfPresent(
        manifest: WorldModelTrainingManifest,
        directory: URL
    ) throws -> StateWorldModelValidationResult? {
        guard manifest.stateWorldModelCheckpointPath != nil || manifest.stateWorldModelConfig != nil else {
            throw TrainingError.missingRequiredStateWorldModel(
                directory.appendingPathComponent("world-model-manifest.json")
            )
        }
        guard let config = manifest.stateWorldModelConfig else {
            throw TrainingError.missingStateWorldModelConfig(
                directory.appendingPathComponent("world-model-manifest.json")
            )
        }
        let checkpointURL = try resolveStateWorldModelCheckpoint(manifest: manifest, directory: directory)
        let stateModel = StateWorldModel(config: config)
        let arrays = try MLX.loadArrays(url: checkpointURL)
        stateModel.update(parameters: ModuleParameters.unflattened(arrays))
        stateModel.train(false)
        eval(stateModel)

        var controller = MLXWorldModelController(model: stateModel, config: config)
        try controller.reset()
        let adapter = try LearnedWorldModelEnvironmentAdapter(
            model: controller,
            timeStep: 0.001
        )
        let validation = try validateStateWorldModelOnManifestDataset(
            adapter: adapter,
            manifest: manifest,
            directory: directory,
            config: config
        )
        return StateWorldModelValidationResult(
            checkpointURL: checkpointURL,
            reason: validation.reason ?? "accepted"
        )
    }

    private func validateStateWorldModelOnManifestDataset(
        adapter: LearnedWorldModelEnvironmentAdapter<MLXWorldModelController>,
        manifest: WorldModelTrainingManifest,
        directory: URL,
        config: WorldModelConfig
    ) throws -> WorldModelAdapterValidation {
        let datasetDirectory = resolveDatasetDirectory(from: manifest.datasetPath, relativeTo: directory)
        let datasets = try loadKuyuTrainingDatasets(from: datasetDirectory)
        let batches = try makeStateWorldModelBatches(
            datasets: datasets,
            config: config,
            sequenceLength: 1,
            maxBatches: 8
        )
        guard !batches.isEmpty else {
            throw TrainingError.emptyWorldModelBatches
        }

        let configuration = WorldModelAdapterConfiguration(
            residualThreshold: 2.0,
            uncertaintyThreshold: 1.0
        )
        var worstResidual = 0.0
        var worstUncertainty = 0.0
        for batch in batches {
            let pairs = try makeValidationReferencePairs(batch: batch, config: config)
            for pair in pairs {
                let prediction = try adapter.predict(reference: pair.physicsPrediction)
                let validation = try adapter.validate(
                    prediction: prediction,
                    reference: pair.actual,
                    configuration: configuration
                )
                worstResidual = max(worstResidual, validation.residualMax)
                worstUncertainty = max(worstUncertainty, validation.uncertainty)
            }
        }
        return WorldModelAdapterValidation(
            accepted: true,
            residualMax: worstResidual,
            uncertainty: worstUncertainty,
            reason: "accepted"
        )
    }

    private func resolveDatasetDirectory(from path: String?, relativeTo directory: URL) -> URL {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return directory
        }
        let url = URL(fileURLWithPath: path)
        if url.path.hasPrefix("/") {
            return url
        }
        return directory.appendingPathComponent(path, isDirectory: true)
    }

    private func makeValidationReferencePairs(
        batch: StateWorldModelTrainingBatch,
        config: WorldModelConfig
    ) throws -> [StateWorldModelValidationPair] {
        eval(batch.physicsStates, batch.sensorObservations, batch.actions, batch.residualTargets)
        let sequenceLength = batch.physicsStates.dim(1)
        let physicsValues = batch.physicsStates.asArray(Float.self)
        let sensorValues = batch.sensorObservations.asArray(Float.self)
        let actionValues = batch.actions.asArray(Float.self)
        let residualValues = batch.residualTargets.asArray(Float.self)
        var pairs: [StateWorldModelValidationPair] = []
        pairs.reserveCapacity(sequenceLength)

        for index in 0..<sequenceLength {
            let physics = slice(
                physicsValues,
                index: index,
                width: config.physicsDimensions
            )
            let residual = slice(
                residualValues,
                index: index,
                width: config.residualDimensions
            )
            let actual = zip(physics, residual).map { physicsValue, residualValue in
                physicsValue + residualValue
            }
            let sensors = slice(
                sensorValues,
                index: index,
                width: config.sensorDimensions
            )
            let actions = slice(
                actionValues,
                index: index,
                width: config.actionDimensions
            )
            let physicsStep = try makeValidationStep(
                state: physics,
                sensors: sensors,
                actions: actions,
                stepIndex: index,
                reward: 0.0
            )
            let actualStep = try makeValidationStep(
                state: actual,
                sensors: sensors,
                actions: actions,
                stepIndex: index,
                reward: 0.0
            )
            pairs.append(StateWorldModelValidationPair(
                physicsPrediction: physicsStep,
                actual: actualStep
            ))
        }
        return pairs
    }

    private func slice(_ values: [Float], index: Int, width: Int) -> [Float] {
        let start = index * width
        let end = start + width
        return Array(values[start..<end])
    }

    private func makeValidationStep(
        state: [Float],
        sensors: [Float],
        actions: [Float],
        stepIndex: Int,
        reward: Double
    ) throws -> EnvironmentStep {
        let time = try WorldTime(
            stepIndex: UInt64(stepIndex + 1),
            time: Double(stepIndex + 1) * 0.001
        )
        let sensorSamples = try sensors.enumerated().map { index, value in
            try ChannelSample(
                channelIndex: UInt32(index),
                value: Double(value),
                timestamp: time.time
            )
        }
        let actuatorValues = try actions.enumerated().map { index, value in
            try ActuatorValue(
                index: KuyuCore.ActuatorIndex(UInt32(index)),
                value: Double(value)
            )
        }
        let log = WorldStepLog(
            time: time,
            events: [],
            sensorSamples: sensorSamples,
            driveIntents: [],
            reflexCorrections: [],
            actuatorValues: actuatorValues,
            actuatorTelemetry: ActuatorTelemetrySnapshot(channels: []),
            safetyTrace: try SafetyTrace(omegaMagnitude: 0.0, tiltRadians: 0.0),
            plantState: plantState(from: state),
            disturbances: DisturbanceSnapshot(
                forceWorld: Axis3(x: 0, y: 0, z: 0),
                torqueBody: Axis3(x: 0, y: 0, z: 0)
            )
        )
        return try EnvironmentStep(
            observation: EnvironmentObservation(log: log),
            reward: reward,
            done: false,
            truncated: false,
            info: EpisodeInfo(
                scenarioId: try ScenarioID("m2-state-world-model-validation"),
                seed: ScenarioSeed(0),
                configHash: "m2-state-world-model-validation",
                stepCount: stepIndex + 1,
                rewardSum: reward
            ),
            log: log
        )
    }

    private func plantState(from values: [Float]) -> PlantStateSnapshot {
        PlantStateSnapshot(
            root: RigidBodySnapshot(
                id: "root",
                position: Axis3(
                    x: Double(values[0]),
                    y: Double(values[1]),
                    z: Double(values[2])
                ),
                velocity: Axis3(
                    x: Double(values[3]),
                    y: Double(values[4]),
                    z: Double(values[5])
                ),
                orientation: QuaternionSnapshot(
                    w: Double(values[6]),
                    x: Double(values[7]),
                    y: Double(values[8]),
                    z: Double(values[9])
                ),
                angularVelocity: Axis3(
                    x: Double(values[10]),
                    y: Double(values[11]),
                    z: Double(values[12])
                )
            )
        )
    }

    private func resolveStateWorldModelCheckpoint(
        manifest: WorldModelTrainingManifest,
        directory: URL
    ) throws -> URL {
        if let path = manifest.stateWorldModelCheckpointPath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        let localURL = directory.appendingPathComponent("state-world-model.safetensors")
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        let expected = manifest.stateWorldModelCheckpointPath.map(URL.init(fileURLWithPath:)) ?? localURL
        throw TrainingError.missingStateWorldModelCheckpoint(expected)
    }

    private func makeSyntheticReferenceStep(config: WorldModelConfig) throws -> EnvironmentStep {
        let log = try makeSyntheticWorldStepLog(config: config)
        return try EnvironmentStep(
            observation: EnvironmentObservation(log: log),
            reward: 0.0,
            done: false,
            truncated: false,
            info: EpisodeInfo(
                scenarioId: try ScenarioID("m2-state-world-model-preflight"),
                seed: ScenarioSeed(0),
                configHash: "m2-state-world-model-preflight",
                stepCount: 1,
                rewardSum: 0.0
            ),
            log: log
        )
    }

    private func makeSyntheticWorldStepLog(config: WorldModelConfig) throws -> WorldStepLog {
        let time = try WorldTime(stepIndex: 1, time: 0.001)
        let samples = try (0..<config.sensorDimensions).map { index in
            try ChannelSample(channelIndex: UInt32(index), value: 0.0, timestamp: time.time)
        }
        let actuators = try (0..<config.actionDimensions).map { index in
            try ActuatorValue(index: KuyuCore.ActuatorIndex(UInt32(index)), value: 0.0)
        }
        return WorldStepLog(
            time: time,
            events: [],
            sensorSamples: samples,
            driveIntents: [],
            reflexCorrections: [],
            actuatorValues: actuators,
            actuatorTelemetry: ActuatorTelemetrySnapshot(channels: []),
            safetyTrace: try SafetyTrace(omegaMagnitude: 0.0, tiltRadians: 0.0),
            plantState: PlantStateSnapshot(
                root: RigidBodySnapshot(
                    id: "root",
                    position: Axis3(x: 0, y: 0, z: 1),
                    velocity: Axis3(x: 0, y: 0, z: 0),
                    orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
                    angularVelocity: Axis3(x: 0, y: 0, z: 0)
                )
            ),
            disturbances: DisturbanceSnapshot(
                forceWorld: Axis3(x: 0, y: 0, z: 0),
                torqueBody: Axis3(x: 0, y: 0, z: 0)
            )
        )
    }

    private func trainStateWorldModelIfAvailable(
        datasetDirectory: URL,
        saveDirectory: URL,
        sequenceLength: Int,
        epochs: Int,
        learningRate: Float,
        maxBatches: Int?
    ) throws -> StateWorldModelTrainingResult? {
        let datasets = try loadKuyuTrainingDatasets(from: datasetDirectory)
        guard datasets.contains(where: { dataset in
            dataset.records.contains { record in
                record.physicsState != nil && record.actualState != nil && record.actionValues != nil
            }
        }) else {
            return nil
        }

        let first = datasets[0]
        let actionDimensions = try stateWorldModelActionDimensions(datasets)
        let config = WorldModelConfig(
            physicsDimensions: 13,
            sensorDimensions: max(first.metadata.channelCount, 1),
            actionDimensions: actionDimensions,
            hiddenDimensions: 32,
            stochasticCategories: 2,
            stochasticClasses: 2,
            residualDimensions: 13,
            extensionDimensions: 1,
            tokenizerLayers: 1,
            physicsEmbedDimensions: 32
        )
        let batches = try makeStateWorldModelBatches(
            datasets: datasets,
            config: config,
            sequenceLength: sequenceLength,
            maxBatches: maxBatches
        )
        guard !batches.isEmpty else { return nil }

        let model = StateWorldModel(config: config)
        let losses = StateWorldModelTrainer.train(
            model: model,
            batches: batches,
            learningRate: learningRate,
            maxGradNorm: nil,
            epochs: epochs
        )
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        let checkpointURL = saveDirectory.appendingPathComponent("state-world-model.safetensors")
        let arrays = Dictionary(model.parameters().flattened(), uniquingKeysWith: { first, _ in first })
        try MLX.save(arrays: arrays, url: checkpointURL)

        return StateWorldModelTrainingResult(
            checkpointURL: checkpointURL,
            losses: losses,
            config: config
        )
    }

    private func validateStateWorldModelDatasetIfPresent(_ datasetDirectory: URL) throws {
        let datasets = try loadKuyuTrainingDatasets(from: datasetDirectory)
        guard datasets.contains(where: { dataset in
            dataset.records.contains { record in
                record.physicsState != nil && record.actualState != nil && record.actionValues != nil
            }
        }) else {
            return
        }
        _ = try stateWorldModelActionDimensions(datasets)
    }

    private func loadKuyuTrainingDatasets(from root: URL) throws -> [TrainingDataset] {
        let fileManager = FileManager.default
        let metaURL = root.appendingPathComponent("meta.json")
        let recordsURL = root.appendingPathComponent("records.jsonl")
        if fileManager.fileExists(atPath: metaURL.path) && fileManager.fileExists(atPath: recordsURL.path) {
            return [try TrainingDataset.load(from: root)]
        }

        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        var datasets: [TrainingDataset] = []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let childMeta = child.appendingPathComponent("meta.json")
            let childRecords = child.appendingPathComponent("records.jsonl")
            guard fileManager.fileExists(atPath: childMeta.path),
                  fileManager.fileExists(atPath: childRecords.path) else {
                continue
            }
            datasets.append(try TrainingDataset.load(from: child))
        }
        return datasets
    }

    private func stateWorldModelActionDimensions(_ datasets: [TrainingDataset]) throws -> Int {
        let dimensions = Set(
            datasets.flatMap { dataset in
                dataset.records.compactMap { record in
                    record.actionValues?.count
                }
            }.filter { $0 > 0 }
        )
        guard !dimensions.isEmpty else {
            return max(datasets.map(\.metadata.driveCount).max() ?? 0, 1)
        }
        guard dimensions.count == 1, let dimension = dimensions.first else {
            throw TrainingError.inconsistentStateWorldModelActionDimensions(Array(dimensions).sorted())
        }
        return dimension
    }

    private func makeStateWorldModelBatches(
        datasets: [TrainingDataset],
        config: WorldModelConfig,
        sequenceLength: Int,
        maxBatches: Int?
    ) throws -> [StateWorldModelTrainingBatch] {
        var batches: [StateWorldModelTrainingBatch] = []
        for dataset in datasets {
            let tuples = try makeStateWorldModelTuples(dataset: dataset, config: config)
            guard !tuples.isEmpty else { continue }
            var start = 0
            while start < tuples.count {
                if let maxBatches, batches.count >= maxBatches { return batches }
                let end = min(start + sequenceLength, tuples.count)
                let slice = Array(tuples[start..<end])
                batches.append(makeBatch(tuples: slice, config: config))
                start = end
            }
        }
        return batches
    }

    private func makeStateWorldModelTuples(
        dataset: TrainingDataset,
        config: WorldModelConfig
    ) throws -> [StateWorldModelTuple] {
        guard dataset.records.count >= 2 else { return [] }
        var tuples: [StateWorldModelTuple] = []
        tuples.reserveCapacity(dataset.records.count - 1)

        for index in 0..<(dataset.records.count - 1) {
            let current = dataset.records[index]
            let next = dataset.records[index + 1]
            guard let physicsState = next.physicsState,
                  let actualState = next.actualState,
                  let actionValues = current.actionValues else {
                throw TrainingError.missingStateWorldModelFields(
                    URL(fileURLWithPath: "\(dataset.metadata.scenarioId)#\(index)")
                )
            }
            guard physicsState.count == config.physicsDimensions else {
                throw TrainingError.invalidStateWorldModelDimensions(
                    URL(fileURLWithPath: "\(dataset.metadata.scenarioId)#physics-\(index)"),
                    expected: config.physicsDimensions,
                    actual: physicsState.count
                )
            }
            guard actualState.count == config.residualDimensions else {
                throw TrainingError.invalidStateWorldModelDimensions(
                    URL(fileURLWithPath: "\(dataset.metadata.scenarioId)#actual-\(index)"),
                    expected: config.residualDimensions,
                    actual: actualState.count
                )
            }

            let residual = zip(actualState, physicsState).map { actual, physics in
                Float(actual - physics)
            }
            tuples.append(StateWorldModelTuple(
                physicsState: physicsState.map(Float.init),
                sensorObservation: sensorVector(current, count: config.sensorDimensions),
                action: padded(actionValues.map(Float.init), count: config.actionDimensions),
                residualTarget: residual
            ))
        }

        return tuples
    }

    private func makeBatch(
        tuples: [StateWorldModelTuple],
        config: WorldModelConfig
    ) -> StateWorldModelTrainingBatch {
        StateWorldModelTrainingBatch(
            physicsStates: MLXArray(tuples.flatMap(\.physicsState), [1, tuples.count, config.physicsDimensions]),
            sensorObservations: MLXArray(tuples.flatMap(\.sensorObservation), [1, tuples.count, config.sensorDimensions]),
            actions: MLXArray(tuples.flatMap(\.action), [1, tuples.count, config.actionDimensions]),
            residualTargets: MLXArray(tuples.flatMap(\.residualTarget), [1, tuples.count, config.residualDimensions])
        )
    }

    private func sensorVector(_ record: TrainingDatasetRecord, count: Int) -> [Float] {
        var values = Array(repeating: Float(0), count: count)
        for sample in record.sensors {
            let index = Int(sample.channelIndex)
            guard values.indices.contains(index) else { continue }
            values[index] = Float(sample.value)
        }
        return values
    }

    private func padded(_ values: [Float], count: Int) -> [Float] {
        if values.count == count { return values }
        if values.count > count { return Array(values.prefix(count)) }
        return values + Array(repeating: Float(0), count: count - values.count)
    }
}

private struct DatasetCollectionDescriptor: Encodable {
    let entries: [Entry]

    init(datasets: [ManasTrainingDataset]) {
        self.entries = datasets.map { dataset in
            Entry(
                schemaVersion: dataset.metadata.schemaVersion,
                scenarioId: dataset.metadata.scenarioId,
                seed: dataset.metadata.seed,
                configHash: dataset.metadata.configHash,
                recordCount: dataset.metadata.recordCount,
                rewardSum: dataset.metadata.rewardSum,
                done: dataset.metadata.done,
                truncated: dataset.metadata.truncated,
                terminalReason: dataset.metadata.terminalReason
            )
        }
    }

    struct Entry: Encodable {
        let schemaVersion: Int
        let scenarioId: String
        let seed: UInt64
        let configHash: String
        let recordCount: Int
        let rewardSum: Double?
        let done: Bool?
        let truncated: Bool?
        let terminalReason: String?
    }
}

private struct StateWorldModelTrainingResult {
    let checkpointURL: URL
    let losses: [Float]
    let config: WorldModelConfig
}

private struct StateWorldModelValidationResult {
    let checkpointURL: URL
    let reason: String
}

private struct StateWorldModelValidationPair {
    let physicsPrediction: EnvironmentStep
    let actual: EnvironmentStep
}

private struct StateWorldModelTuple {
    let physicsState: [Float]
    let sensorObservation: [Float]
    let action: [Float]
    let residualTarget: [Float]
}
