import Foundation
import Logging
import ManasCore
import ManasMLXModels
import ManasMLXTraining
import MLX
import MLXNN
import KuyuCore
import KuyuProfiles

@MainActor
public final class ManasMLXModelStore {
    private let lock = NSLock()
    private let logger = Logger(label: "kuyu.manas")
    private let uiLogger = Logger(label: "kuyu.ui")
    private var coreModel: ManasMLXCore?
    private var coreConfig: ManasMLXCoreConfig?
    private var reflexModel: ManasMLXReflex?
    private var reflexConfig: ManasMLXReflexConfig?
    private var isBusy: Bool = false

    public var currentCoreConfig: ManasMLXCoreConfig? { coreConfig }
    public var currentReflexConfig: ManasMLXReflexConfig? { reflexConfig }

    public init() {}

    public func runManasMLX(
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        request: SimulationRunRequest,
        descriptor: RobotDescriptor?,
        control: SimulationControl?,
        telemetry: ((WorldStepLog) -> Void)? = nil
    ) async throws -> KuyAtt1RunOutput {
        try beginExclusive()
        defer { endExclusive() }

        var bundle = Imu6NerveBundle(configuration: .init(
            gyroRange: -20...20,
            accelRange: -20...20
        ))
        var gate: any Gating = request.useQualityGating
            ? QualityGating(configuration: .init(minGate: 0.2, maxGate: 1.0))
            : IdentityGating()
        var trunks = BasicTrunksBuilder()
        let sizing = try ManasMLXCut.computeSizing(bundle: &bundle, gate: &gate, trunks: &trunks)
        let driveCount = request.taskMode == .singleLift ? 1 : sizing.driveCount

        let core = prepareCore(
            inputSize: sizing.trunkSize,
            driveCount: driveCount,
            auxEnabled: request.useAux
        )
        let reflex = prepareReflex(inputSize: sizing.fastTapCount, driveCount: driveCount)

        let definitions: [ReferenceQuadrotorScenarioDefinition]
        switch request.taskMode {
        case .lift:
            definitions = try KuyLiftSuite().scenarios()
        case .singleLift:
            definitions = try KuySingleLiftSuite().scenarios()
        case .attitude:
            definitions = try KuyAtt1Suite().scenarios()
        }
        let manifest = ReferenceQuadrotorScenarioManifestBuilder().build(from: definitions)

        var evaluations: [ScenarioEvaluation] = []
        let replayChecks: [ReplayCheckResult] = []
        var logs: [ScenarioLogEntry] = []

        logger.notice("ManasMLX run started", metadata: [
            "scenarios": "\(definitions.count)",
            "controller": "ManasMLX",
            "task": .string(request.taskMode.rawValue),
            "driveCount": .string("\(driveCount)")
        ])

        switch request.taskMode {
        case .lift:
            if let chainFactory = motorNerveChainFactory(
                descriptor: descriptor,
                request: request,
                expectedDriveCount: driveCount,
                fallbackProfile: "lift"
            ) {
                let runner = ReferenceQuadrotorScenarioRunner<ManasMLXCut, MotorNerveChain>(
                    parameters: parameters,
                    schedule: schedule,
                    determinism: request.determinism,
                    noise: request.noise,
                    hoverThrustScale: request.gains.hoverThrustScale
                )
                for definition in definitions {
                    if let control {
                        try await control.checkpoint()
                    }
                    let cut = try ManasMLXCut(
                        coreModel: core,
                        reflexModel: reflex,
                        useQualityGating: request.useQualityGating
                    )
                    let log = try await runner.runScenario(
                        definition: definition,
                        cut: cut,
                        motorNerve: try chainFactory(),
                        control: control,
                        telemetry: telemetry
                    )
                    let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
                    logs.append(ScenarioLogEntry(key: key, log: log))
                    if let reason = log.failureReason {
                        logger.warning("Scenario failed", metadata: [
                            "scenario": .string(definition.config.id.rawValue),
                            "seed": .string("\(definition.config.seed.rawValue)"),
                            "reason": .string(reason.rawValue),
                            "time": .string(String(format: "%.2f", log.failureTime ?? 0))
                        ])
                    }
                    let evaluation = ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log)
                    evaluations.append(evaluation)
                    await Task.yield()
                }
                break
            }
            let runner = ReferenceQuadrotorScenarioRunner<ManasMLXCut, LiftMotorNerve>(
                parameters: parameters,
                schedule: schedule,
                determinism: request.determinism,
                noise: request.noise,
                hoverThrustScale: request.gains.hoverThrustScale
            )
            for definition in definitions {
                if let control {
                    try await control.checkpoint()
                }
                let cut = try ManasMLXCut(
                    coreModel: core,
                    reflexModel: reflex,
                    useQualityGating: request.useQualityGating
                )
                let maxThrusts = try MotorMaxThrusts.uniform(parameters.maxThrust)
                let log = try await runner.runScenario(
                    definition: definition,
                    cut: cut,
                    motorNerve: LiftMotorNerve(motorMaxThrusts: maxThrusts),
                    control: control,
                    telemetry: telemetry
                )
                let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
                logs.append(ScenarioLogEntry(key: key, log: log))
                if let reason = log.failureReason {
                    logger.warning("Scenario failed", metadata: [
                        "scenario": .string(definition.config.id.rawValue),
                        "seed": .string("\(definition.config.seed.rawValue)"),
                        "reason": .string(reason.rawValue),
                        "time": .string(String(format: "%.2f", log.failureTime ?? 0))
                    ])
                }
                let evaluation = ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log)
                evaluations.append(evaluation)
                await Task.yield()
            }
        case .singleLift:
            if let chainFactory = motorNerveChainFactory(
                descriptor: descriptor,
                request: request,
                expectedDriveCount: driveCount,
                fallbackProfile: "fixed-single-prop"
            ) {
                let runner = ReferenceQuadrotorScenarioRunner<ManasMLXCut, MotorNerveChain>(
                    parameters: parameters,
                    schedule: schedule,
                    determinism: request.determinism,
                    noise: request.noise,
                    hoverThrustScale: request.gains.hoverThrustScale
                )
                for definition in definitions {
                    if let control {
                        try await control.checkpoint()
                    }
                    let cut = try ManasMLXCut(
                        coreModel: core,
                        reflexModel: reflex,
                        useQualityGating: request.useQualityGating
                    )
                    let log = try await runner.runScenario(
                        definition: definition,
                        cut: cut,
                        motorNerve: try chainFactory(),
                        control: control,
                        telemetry: telemetry
                    )
                    let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
                    logs.append(ScenarioLogEntry(key: key, log: log))
                    if let reason = log.failureReason {
                        logger.warning("Scenario failed", metadata: [
                            "scenario": .string(definition.config.id.rawValue),
                            "seed": .string("\(definition.config.seed.rawValue)"),
                            "reason": .string(reason.rawValue),
                            "time": .string(String(format: "%.2f", log.failureTime ?? 0))
                        ])
                    }
                    let evaluation = ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log)
                    evaluations.append(evaluation)
                    await Task.yield()
                }
                break
            }
            let runner = ReferenceQuadrotorScenarioRunner<ManasMLXCut, FixedSinglePropMotorNerve>(
                parameters: parameters,
                schedule: schedule,
                determinism: request.determinism,
                noise: request.noise,
                hoverThrustScale: request.gains.hoverThrustScale
            )
            for definition in definitions {
                if let control {
                    try await control.checkpoint()
                }
                let cut = try ManasMLXCut(
                    coreModel: core,
                    reflexModel: reflex,
                    useQualityGating: request.useQualityGating
                )
                let baseThrottle = 0.0
                let motorNerveConfig = FixedSinglePropMotorNerve.Config(
                    maxThrust: parameters.maxThrust,
                    baseThrottle: baseThrottle
                )
                let log = try await runner.runScenario(
                    definition: definition,
                    cut: cut,
                    motorNerve: FixedSinglePropMotorNerve(config: motorNerveConfig),
                    control: control,
                    telemetry: telemetry
                )
                let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
                logs.append(ScenarioLogEntry(key: key, log: log))
                if let reason = log.failureReason {
                    logger.warning("Scenario failed", metadata: [
                        "scenario": .string(definition.config.id.rawValue),
                        "seed": .string("\(definition.config.seed.rawValue)"),
                        "reason": .string(reason.rawValue),
                        "time": .string(String(format: "%.2f", log.failureTime ?? 0))
                    ])
                }
                let evaluation = ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log)
                evaluations.append(evaluation)
                await Task.yield()
            }
        case .attitude:
            if let chainFactory = motorNerveChainFactory(
                descriptor: descriptor,
                request: request,
                expectedDriveCount: driveCount,
                fallbackProfile: "fixed-quad"
            ) {
                let runner = ReferenceQuadrotorScenarioRunner<ManasMLXCut, MotorNerveChain>(
                    parameters: parameters,
                    schedule: schedule,
                    determinism: request.determinism,
                    noise: request.noise,
                    hoverThrustScale: request.gains.hoverThrustScale
                )
                for definition in definitions {
                    if let control {
                        try await control.checkpoint()
                    }
                    let cut = try ManasMLXCut(
                        coreModel: core,
                        reflexModel: reflex,
                        useQualityGating: request.useQualityGating
                    )
                    let log = try await runner.runScenario(
                        definition: definition,
                        cut: cut,
                        motorNerve: try chainFactory(),
                        control: control,
                        telemetry: telemetry
                    )
                    let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
                    logs.append(ScenarioLogEntry(key: key, log: log))
                    if let reason = log.failureReason {
                        logger.warning("Scenario failed", metadata: [
                            "scenario": .string(definition.config.id.rawValue),
                            "seed": .string("\(definition.config.seed.rawValue)"),
                            "reason": .string(reason.rawValue),
                            "time": .string(String(format: "%.2f", log.failureTime ?? 0))
                        ])
                    }
                    let evaluation = ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log)
                    evaluations.append(evaluation)
                    await Task.yield()
                }
                break
            }
            let maxThrusts = try MotorMaxThrusts.uniform(parameters.maxThrust)
            let motorNerveConfig = FixedQuadMotorNerve.Config(
                mixer: ReferenceQuadrotorMixer(armLength: parameters.armLength, yawCoefficient: parameters.yawCoefficient),
                motorMaxThrusts: maxThrusts
            )
            let runner = ReferenceQuadrotorScenarioRunner<ManasMLXCut, FixedQuadMotorNerve>(
                parameters: parameters,
                schedule: schedule,
                determinism: request.determinism,
                noise: request.noise,
                hoverThrustScale: request.gains.hoverThrustScale
            )
            for definition in definitions {
                if let control {
                    try await control.checkpoint()
                }
                let cut = try ManasMLXCut(
                    coreModel: core,
                    reflexModel: reflex,
                    useQualityGating: request.useQualityGating
                )
                let log = try await runner.runScenario(
                    definition: definition,
                    cut: cut,
                    motorNerve: FixedQuadMotorNerve(config: motorNerveConfig),
                    control: control,
                    telemetry: telemetry
                )
                let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
                logs.append(ScenarioLogEntry(key: key, log: log))
                if let reason = log.failureReason {
                    logger.warning("Scenario failed", metadata: [
                        "scenario": .string(definition.config.id.rawValue),
                        "seed": .string("\(definition.config.seed.rawValue)"),
                        "reason": .string(reason.rawValue),
                        "time": .string(String(format: "%.2f", log.failureTime ?? 0))
                    ])
                }
                let evaluation = ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log)
                evaluations.append(evaluation)
                await Task.yield()
            }
        }

        let evaluationPass = evaluations.allSatisfy { $0.passed }
        let replayPass = replayChecks.allSatisfy { $0.passed }
        let result = SuiteRunResult(evaluations: evaluations, replayChecks: replayChecks, passed: evaluationPass && replayPass)

        let aggregate = EvaluationAggregate.from(evaluations: result.evaluations)
        let summary = ValidationSummary(
            suitePassed: result.passed,
            evaluations: result.evaluations,
            replayChecks: result.replayChecks,
            manifest: manifest,
            aggregate: aggregate
        )

        logger.notice("ManasMLX run completed", metadata: [
            "passed": "\(summary.suitePassed)",
            "scenarios": "\(logs.count)"
        ])

        return KuyAtt1RunOutput(result: result, summary: summary, logs: logs)
    }

    private func motorNerveChainFactory(
        descriptor: RobotDescriptor?,
        request: SimulationRunRequest,
        expectedDriveCount: Int,
        fallbackProfile: String
    ) -> (() throws -> MotorNerveChain)? {
        guard let descriptor else { return nil }
        let modelPath = request.modelDescriptorPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if descriptor.control.driveChannels.count != expectedDriveCount {
            uiLogger.warning("MotorNerveChain disabled due to drive count mismatch", metadata: [
                "action": "motorNerveFallback",
                "task": .string(request.taskMode.rawValue),
                "model": .string(modelPath),
                "from": "descriptor-chain",
                "to": .string(fallbackProfile),
                "reason": "driveCountMismatch",
                "motorNerveProfile": .string(fallbackProfile)
            ])
            return nil
        }

        if descriptor.motorNerve.stages.contains(where: { $0.type == .custom }) {
            uiLogger.warning("MotorNerveChain disabled due to unsupported stage", metadata: [
                "action": "motorNerveFallback",
                "task": .string(request.taskMode.rawValue),
                "model": .string(modelPath),
                "from": "descriptor-chain",
                "to": .string(fallbackProfile),
                "reason": "unsupportedCustomStage",
                "motorNerveProfile": .string(fallbackProfile)
            ])
            return nil
        }

        uiLogger.notice("MotorNerveChain enabled", metadata: [
            "action": "motorNerveChain",
            "task": .string(request.taskMode.rawValue),
            "model": .string(modelPath),
            "motorNerveProfile": "descriptor-chain"
        ])

        return { try MotorNerveChain(descriptor: descriptor) }
    }

    public func trainCore(
        datasetURL: URL,
        sequenceLength: Int,
        learningRate: Double,
        epochs: Int,
        useAux: Bool,
        useQualityGating: Bool
    ) async throws -> TrainingResult {
        try beginExclusive()
        defer { endExclusive() }

        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let maxBatches = isPreview ? 8 : nil

        let datasets = try loadTrainingDatasets(from: datasetURL)
        let driveCount = datasets.first?.metadata.driveCount ?? 0
        guard driveCount > 0 else {
            throw NSError(domain: "kuyu.ui", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid drive count"])
        }

        logger.notice("ManasMLX training started", metadata: [
            "datasets": "\(datasets.count)",
            "driveCount": "\(driveCount)",
            "epochs": "\(epochs)",
            "sequence": "\(sequenceLength)",
            "aux": "\(useAux)"
        ])

        var allBatches: [ManasMLXSequenceBatch] = []
        var allAuxBatches: [ManasMLXAuxSequenceBatch] = []
        var trunkSize: Int?

        for dataset in datasets {
            var pipeline = buildTrainingPipeline(useQualityGating: useQualityGating)
            let builder = ManasTrainingBatchBuilder(
                sequenceLength: sequenceLength,
                driveCount: driveCount,
                maxBatches: maxBatches
            )
            if useAux {
                let auxBatches = try builder.makeAuxBatches(dataset: dataset, pipeline: &pipeline)
                if trunkSize == nil, let batch = auxBatches.first {
                    trunkSize = batch.trunks.shape.last
                }
                allAuxBatches.append(contentsOf: auxBatches)
            } else {
                let batches = try builder.makeCoreBatches(dataset: dataset, pipeline: &pipeline)
                if trunkSize == nil, let batch = batches.first {
                    trunkSize = batch.trunks.shape.last
                }
                allBatches.append(contentsOf: batches)
            }
            if let maxBatches, (allBatches.count + allAuxBatches.count) >= maxBatches {
                break
            }
        }

        guard let inputSize = trunkSize else {
            throw NSError(domain: "kuyu.ui", code: 3, userInfo: [NSLocalizedDescriptionKey: "No training batches produced"])
        }

        let core = prepareCore(inputSize: inputSize, driveCount: driveCount, auxEnabled: useAux)
        let trainConfig = ManasMLXTrainingConfig(
            epochs: epochs,
            learningRate: Float(learningRate)
        )

        let losses: [Float]
        let batchCount = allAuxBatches.isEmpty ? allBatches.count : allAuxBatches.count
        let logStride = max(1, batchCount / 20)
        logger.notice("ManasMLX training batches", metadata: [
            "batches": .string("\(batchCount)"),
            "learningRate": .string(String(format: "%.6f", learningRate))
        ])

        if useAux {
            losses = try await ManasMLXTrainer.trainCoreWithAuxAsync(
                model: core,
                batches: allAuxBatches,
                config: trainConfig
            ) { [logger] epoch, batch, total, loss in
                if batch % logStride == 0 || batch == total {
                    logger.notice("ManasMLX training progress", metadata: [
                        "epoch": "\(epoch)",
                        "batch": "\(batch)",
                        "total": "\(total)",
                        "loss": .string(String(format: "%.6f", loss))
                    ])
                }
            }
        } else {
            losses = await ManasMLXTrainer.trainCoreSupervisedAsync(
                model: core,
                batches: allBatches,
                config: trainConfig
            ) { [logger] epoch, batch, total, loss in
                if batch % logStride == 0 || batch == total {
                    logger.notice("ManasMLX training progress", metadata: [
                        "epoch": "\(epoch)",
                        "batch": "\(batch)",
                        "total": "\(total)",
                        "loss": .string(String(format: "%.6f", loss))
                    ])
                }
            }
        }

        logger.notice("ManasMLX training completed", metadata: [
            "finalLoss": .string(String(format: "%.6f", losses.last ?? 0)),
            "epochs": .string("\(epochs)")
        ])

        return TrainingResult(finalLoss: Double(losses.last ?? 0), epochs: epochs)
    }

    public func saveModel(to directory: URL, manifest: ManasMLXModelManifest) throws {
        guard let coreModel else {
            throw NSError(domain: "kuyu.manas", code: 10, userInfo: [NSLocalizedDescriptionKey: "Core model not initialized"])
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestURL = directory.appendingPathComponent("model.json")
        try encoder.encode(manifest).write(to: manifestURL)

        let coreArrays = Dictionary(uniqueKeysWithValues: coreModel.parameters().flattened())
        let coreURL = directory.appendingPathComponent("core.safetensors")
        try MLX.save(arrays: coreArrays, url: coreURL)

        if let reflexModel, manifest.reflexConfig != nil {
            let reflexArrays = Dictionary(uniqueKeysWithValues: reflexModel.parameters().flattened())
            let reflexURL = directory.appendingPathComponent("reflex.safetensors")
            try MLX.save(arrays: reflexArrays, url: reflexURL)
        }
    }

    @discardableResult
    public func loadModel(from directory: URL) throws -> ManasMLXModelManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifestURL = directory.appendingPathComponent("model.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(ManasMLXModelManifest.self, from: data)

        let coreURL = directory.appendingPathComponent("core.safetensors")
        let core = ManasMLXCore(config: manifest.coreConfig)
        let coreArrays = try MLX.loadArrays(url: coreURL)
        let coreParameters = ModuleParameters.unflattened(coreArrays)
        core.update(parameters: coreParameters)

        coreModel = core
        coreConfig = manifest.coreConfig

        if let reflexConfig = manifest.reflexConfig {
            let reflexURL = directory.appendingPathComponent("reflex.safetensors")
            if FileManager.default.fileExists(atPath: reflexURL.path) {
                let reflex = ManasMLXReflex(config: reflexConfig)
                let reflexArrays = try MLX.loadArrays(url: reflexURL)
                let reflexParameters = ModuleParameters.unflattened(reflexArrays)
                reflex.update(parameters: reflexParameters)
                reflexModel = reflex
                self.reflexConfig = reflexConfig
            }
        }

        return manifest
    }

    private func prepareCore(inputSize: Int, driveCount: Int, auxEnabled: Bool) -> ManasMLXCore {
        let config = ManasMLXCoreConfig(
            inputSize: inputSize,
            embeddingSize: 128,
            fastHiddenSize: 256,
            slowHiddenSize: 128,
            driveCount: driveCount,
            driveScale: 1.0,
            auxSize: inputSize,
            auxEnabled: auxEnabled
        )
        return withLock {
            if let model = coreModel, coreConfig == config {
                return model
            }
            let model = ManasMLXCore(config: config)
            coreModel = model
            coreConfig = config
            return model
        }
    }

    private func prepareReflex(inputSize: Int, driveCount: Int) -> ManasMLXReflex {
        let config = ManasMLXReflexConfig(inputSize: inputSize, driveCount: driveCount)
        return withLock {
            if let model = reflexModel, reflexConfig == config {
                return model
            }
            let model = ManasMLXReflex(config: config)
            reflexModel = model
            reflexConfig = config
            return model
        }
    }

    private func loadTrainingDatasets(from root: URL) throws -> [ManasTrainingDataset] {
        let fileManager = FileManager.default
        let metaURL = root.appendingPathComponent("meta.json")
        let recordsURL = root.appendingPathComponent("records.jsonl")

        if fileManager.fileExists(atPath: metaURL.path) && fileManager.fileExists(atPath: recordsURL.path) {
            return [try ManasTrainingDataset.load(from: root)]
        }

        let items = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let datasets = try items.compactMap { url -> ManasTrainingDataset? in
            let meta = url.appendingPathComponent("meta.json")
            let records = url.appendingPathComponent("records.jsonl")
            guard fileManager.fileExists(atPath: meta.path),
                  fileManager.fileExists(atPath: records.path) else {
                return nil
            }
            return try ManasTrainingDataset.load(from: url)
        }
        guard !datasets.isEmpty else {
            throw NSError(domain: "kuyu.ui", code: 1, userInfo: [NSLocalizedDescriptionKey: "No training datasets found"])
        }
        return datasets
    }

    private func buildTrainingPipeline(useQualityGating: Bool) -> ManasTrunkPipeline {
        let bundle = Imu6NerveBundle(configuration: .init(
            gyroRange: -20...20,
            accelRange: -20...20
        ))
        let gate: any Gating = useQualityGating
            ? QualityGating(configuration: .init(minGate: 0.2, maxGate: 1.0))
            : IdentityGating()
        let trunks = BasicTrunksBuilder()
        return ManasTrunkPipeline(bundle: bundle, gate: gate, trunks: trunks)
    }

    private func beginExclusive() throws {
        try withLock {
            if isBusy {
                throw NSError(domain: "kuyu.ui", code: 10, userInfo: [NSLocalizedDescriptionKey: "Model store is busy"])
            }
            isBusy = true
        }
    }

    private func endExclusive() {
        withLock {
            isBusy = false
        }
    }

    @discardableResult
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
