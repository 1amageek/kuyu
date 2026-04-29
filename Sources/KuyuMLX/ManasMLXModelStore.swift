import Foundation
import Logging
import ManasCore
import ManasMLXModels
import ManasMLXTraining
import ManasTrainingData
import MLX
import MLXNN
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public enum ModelStoreError: Error, Equatable {
    case busy
    case coreModelNotInitialized
    case invalidDriveCount
    case noBatchesProduced
    case noTrainingDatasetsFound
}

@MainActor
public final class ManasMLXModelStore {
    private let logger = Logger(label: "kuyu.manas")
    private let uiLogger = Logger(label: "kuyu.ui")
    private var coreModel: ManasMLXCore?
    private var coreConfig: ManasMLXCoreConfig?
    private var reflexModel: ManasMLXReflex?
    private var reflexConfig: ManasMLXReflexConfig?
    private var currentDescriptor: RobotDescriptor?
    private var isBusy = false

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

        let observationMode = ManasMLXObservationMode.runtimeMode(for: request.taskMode)
        let sizing = try ManasMLXCut.computeSizing(
            observationMode: observationMode,
            useQualityGating: request.useQualityGating
        )
        let driveCount = request.taskMode == .singleLift ? 1 : sizing.driveCount

        let core = prepareCore(
            inputSize: sizing.trunkSize,
            driveCount: driveCount,
            auxEnabled: request.useAux,
            descriptor: descriptor
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
        var replayChecks: [ReplayCheckResult] = []
        var logs: [ScenarioLogEntry] = []

        logger.notice("ManasMLX run started", metadata: [
            "scenarios": "\(definitions.count)",
            "controller": "ManasMLX",
            "task": .string(request.taskMode.rawValue),
            "observation": .string("\(observationMode)"),
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
                        useQualityGating: request.useQualityGating,
                        observationMode: observationMode,
                        descendingVector: request.descendingVector,
                        descendingProgram: request.descendingProgram
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
                    let replayLog = try await runner.runScenario(
                        definition: definition,
                        cut: try ManasMLXCut(
                            coreModel: core,
                            reflexModel: reflex,
                            useQualityGating: request.useQualityGating,
                            observationMode: observationMode,
                            descendingVector: request.descendingVector,
                            descendingProgram: request.descendingProgram
                    ),
                        motorNerve: try chainFactory(),
                        control: nil,
                        telemetry: nil
                    )
                    replayChecks.append(try ReplayChecker().check(reference: log, candidate: replayLog))
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
                    useQualityGating: request.useQualityGating,
                    observationMode: observationMode,
                    descendingVector: request.descendingVector,
                    descendingProgram: request.descendingProgram
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
                let replayCut = try ManasMLXCut(
                    coreModel: core,
                    reflexModel: reflex,
                    useQualityGating: request.useQualityGating,
                    observationMode: observationMode,
                    descendingVector: request.descendingVector,
                    descendingProgram: request.descendingProgram
                    )
                let replayLog = try await runner.runScenario(
                    definition: definition,
                    cut: replayCut,
                    motorNerve: LiftMotorNerve(motorMaxThrusts: maxThrusts),
                    control: nil,
                    telemetry: nil
                )
                replayChecks.append(try ReplayChecker().check(reference: log, candidate: replayLog))
                await Task.yield()
            }
        case .singleLift:
            let tunedParameters = try KuyuSingleLiftParameterTuning.tuned(
                parameters: parameters,
                hoverThrustScale: request.gains.hoverThrustScale
            )
            if let chainFactory = motorNerveChainFactory(
                descriptor: descriptor,
                request: request,
                expectedDriveCount: driveCount,
                fallbackProfile: "fixed-single-prop"
            ) {
                let runner = ReferenceQuadrotorScenarioRunner<ManasMLXCut, MotorNerveChain>(
                    parameters: tunedParameters,
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
                        useQualityGating: request.useQualityGating,
                        observationMode: observationMode,
                        descendingVector: request.descendingVector,
                        descendingProgram: request.descendingProgram
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
                    let replayLog = try await runner.runScenario(
                        definition: definition,
                        cut: try ManasMLXCut(
                            coreModel: core,
                            reflexModel: reflex,
                            useQualityGating: request.useQualityGating,
                            observationMode: observationMode,
                            descendingVector: request.descendingVector,
                            descendingProgram: request.descendingProgram
                    ),
                        motorNerve: try chainFactory(),
                        control: nil,
                        telemetry: nil
                    )
                    replayChecks.append(try ReplayChecker().check(reference: log, candidate: replayLog))
                    await Task.yield()
                }
                break
            }
            let runner = ReferenceQuadrotorScenarioRunner<ManasMLXCut, FixedSinglePropMotorNerve>(
                parameters: tunedParameters,
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
                    useQualityGating: request.useQualityGating,
                    observationMode: observationMode,
                    descendingVector: request.descendingVector,
                    descendingProgram: request.descendingProgram
                    )
                let baseThrottle = 0.0
                let motorNerveConfig = FixedSinglePropMotorNerve.Config(
                    maxThrust: tunedParameters.maxThrust,
                    rateLimitPerSecond: 100.0,
                    smoothingTimeConstant: nil,
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
                let replayCut = try ManasMLXCut(
                    coreModel: core,
                    reflexModel: reflex,
                    useQualityGating: request.useQualityGating,
                    observationMode: observationMode,
                    descendingVector: request.descendingVector,
                    descendingProgram: request.descendingProgram
                    )
                let replayLog = try await runner.runScenario(
                    definition: definition,
                    cut: replayCut,
                    motorNerve: FixedSinglePropMotorNerve(config: motorNerveConfig),
                    control: nil,
                    telemetry: nil
                )
                replayChecks.append(try ReplayChecker().check(reference: log, candidate: replayLog))
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
                        useQualityGating: request.useQualityGating,
                        observationMode: observationMode,
                        descendingVector: request.descendingVector,
                        descendingProgram: request.descendingProgram
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
                    let replayLog = try await runner.runScenario(
                        definition: definition,
                        cut: try ManasMLXCut(
                            coreModel: core,
                            reflexModel: reflex,
                            useQualityGating: request.useQualityGating,
                            observationMode: observationMode,
                            descendingVector: request.descendingVector,
                            descendingProgram: request.descendingProgram
                    ),
                        motorNerve: try chainFactory(),
                        control: nil,
                        telemetry: nil
                    )
                    replayChecks.append(try ReplayChecker().check(reference: log, candidate: replayLog))
                    await Task.yield()
                }
                break
            }
            let maxThrusts = try MotorMaxThrusts.uniform(parameters.maxThrust)
            let motorNerveConfig = FixedQuadMotorNerve.Config(
                mixer: ReferenceQuadrotorMixer(armLength: parameters.armLength, yawCoefficient: parameters.yawCoefficient),
                motorMaxThrusts: maxThrusts,
                rateLimitPerSecond: 100.0,
                smoothingTimeConstant: nil
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
                    useQualityGating: request.useQualityGating,
                    observationMode: observationMode,
                    descendingVector: request.descendingVector,
                    descendingProgram: request.descendingProgram
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
                let replayCut = try ManasMLXCut(
                    coreModel: core,
                    reflexModel: reflex,
                    useQualityGating: request.useQualityGating,
                    observationMode: observationMode,
                    descendingVector: request.descendingVector,
                    descendingProgram: request.descendingProgram
                    )
                let replayLog = try await runner.runScenario(
                    definition: definition,
                    cut: replayCut,
                    motorNerve: FixedQuadMotorNerve(config: motorNerveConfig),
                    control: nil,
                    telemetry: nil
                )
                replayChecks.append(try ReplayChecker().check(reference: log, candidate: replayLog))
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
        useQualityGating: Bool,
        maxBatches: Int? = nil
    ) async throws -> TrainingResult {
        try beginExclusive()
        defer { endExclusive() }

        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let effectiveMaxBatches = maxBatches ?? (isPreview ? 8 : nil)

        let datasets = try loadTrainingDatasets(from: datasetURL)
        let driveCount = datasets.first?.metadata.driveCount ?? 0
        guard driveCount > 0 else {
            throw ModelStoreError.invalidDriveCount
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
        var batchGroups: [[ManasMLXSequenceBatch]] = []
        var auxBatchGroups: [[ManasMLXAuxSequenceBatch]] = []
        var trunkSize: Int?
        let observationMode = ManasMLXObservationMode.trainingMode(
            channelCount: datasets.first?.metadata.channelCount ?? 0,
            driveCount: driveCount
        )

        let perDatasetMaxBatches = effectiveMaxBatches.map { limit in
            max(1, Int(ceil(Double(limit) / Double(max(datasets.count, 1)))))
        }

        for dataset in datasets {
            var pipeline = buildTrainingPipeline(
                useQualityGating: useQualityGating,
                observationMode: observationMode
            )
            let builder = ManasTrainingBatchBuilder(
                sequenceLength: sequenceLength,
                driveCount: driveCount,
                maxBatches: perDatasetMaxBatches
            )
            if useAux {
                let auxBatches = try builder.makeAuxBatches(dataset: dataset, pipeline: &pipeline)
                if trunkSize == nil, let batch = auxBatches.first {
                    trunkSize = batch.trunks.shape.last
                }
                auxBatchGroups.append(auxBatches)
            } else {
                let batches = try builder.makeCoreBatches(dataset: dataset, pipeline: &pipeline)
                if trunkSize == nil, let batch = batches.first {
                    trunkSize = batch.trunks.shape.last
                }
                batchGroups.append(batches)
            }
        }

        allBatches = cappedBatches(interleavedBatches(batchGroups), limit: effectiveMaxBatches, currentCount: 0)
        allAuxBatches = cappedBatches(interleavedBatches(auxBatchGroups), limit: effectiveMaxBatches, currentCount: 0)

        guard let inputSize = trunkSize else {
            throw ModelStoreError.noBatchesProduced
        }

        let core = prepareCore(inputSize: inputSize, driveCount: driveCount, auxEnabled: useAux)
        let sizing = try ManasMLXCut.computeSizing(
            observationMode: observationMode,
            useQualityGating: useQualityGating
        )
        _ = prepareReflex(inputSize: sizing.fastTapCount, driveCount: driveCount)
        let trainConfig = ManasMLXTrainingConfig(
            epochs: epochs,
            learningRate: Float(learningRate)
        )

        let losses: [Float]
        let batchCount = allAuxBatches.isEmpty ? allBatches.count : allAuxBatches.count
        let logStride = max(1, batchCount / 4)
        logger.notice("ManasMLX training batches", metadata: [
            "batches": .string("\(batchCount)"),
            "observation": .string("\(observationMode)"),
            "learningRate": .string(String(format: "%.6f", learningRate))
        ])

        if useAux {
            losses = try await ManasMLXTrainer.trainCoreWithAuxAsync(
                model: core,
                batches: allAuxBatches,
                config: trainConfig
            ) { [logger] epoch, batch, total, loss in
                let shouldLogBatch = epoch == 1 && (batch % logStride == 0 || batch == total)
                let shouldLogEpoch = batch == total && (epoch % 5 == 0 || epoch == epochs)
                if shouldLogBatch || shouldLogEpoch {
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
                let shouldLogBatch = epoch == 1 && (batch % logStride == 0 || batch == total)
                let shouldLogEpoch = batch == total && (epoch % 5 == 0 || epoch == epochs)
                if shouldLogBatch || shouldLogEpoch {
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

    public func makeManifest(name: String = "manas-core") throws -> ManasMLXModelManifest {
        try beginExclusive()
        defer { endExclusive() }

        return try makeManifestUnlocked(name: name)
    }

    @discardableResult
    public func saveModel(
        to directory: URL,
        name: String = "manas-core",
        createdAt: Date? = nil,
        lastTrainedAt: Date? = nil
    ) throws -> ManasMLXModelManifest {
        try beginExclusive()
        defer { endExclusive() }

        let manifest = try makeManifestUnlocked(
            name: name,
            createdAt: createdAt ?? Date(),
            lastTrainedAt: lastTrainedAt ?? Date()
        )
        try saveModelUnlocked(to: directory, manifest: manifest)
        return manifest
    }

    public func saveModel(to directory: URL, manifest: ManasMLXModelManifest) throws {
        try beginExclusive()
        defer { endExclusive() }

        try saveModelUnlocked(to: directory, manifest: manifest)
    }

    private func makeManifestUnlocked(
        name: String,
        createdAt: Date = Date(),
        lastTrainedAt: Date = Date()
    ) throws -> ManasMLXModelManifest {
        guard let coreConfig else {
            throw ModelStoreError.coreModelNotInitialized
        }
        return ManasMLXModelManifest(
            name: name,
            createdAt: createdAt,
            lastTrainedAt: lastTrainedAt,
            coreConfig: coreConfig,
            reflexConfig: reflexConfig
        )
    }

    private func saveModelUnlocked(to directory: URL, manifest: ManasMLXModelManifest) throws {
        guard let coreModel else {
            throw ModelStoreError.coreModelNotInitialized
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestURL = directory.appendingPathComponent("model.json")
        try encoder.encode(manifest).write(to: manifestURL)

        let coreArrays = Dictionary(coreModel.parameters().flattened(), uniquingKeysWith: { first, _ in first })
        let coreURL = directory.appendingPathComponent("core.safetensors")
        try MLX.save(arrays: coreArrays, url: coreURL)

        if let reflexModel, manifest.reflexConfig != nil {
            let reflexArrays = Dictionary(reflexModel.parameters().flattened(), uniquingKeysWith: { first, _ in first })
            let reflexURL = directory.appendingPathComponent("reflex.safetensors")
            try MLX.save(arrays: reflexArrays, url: reflexURL)
        }
    }

    @discardableResult
    public func loadModel(from directory: URL) throws -> ManasMLXModelManifest {
        try beginExclusive()
        defer { endExclusive() }

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

    private func prepareCore(
        inputSize: Int,
        driveCount: Int,
        auxEnabled: Bool,
        descriptor: RobotDescriptor? = nil
    ) -> ManasMLXCore {
        let config = Self.makeCoreConfig(
            inputSize: inputSize,
            driveCount: driveCount,
            auxEnabled: auxEnabled,
            descriptor: descriptor ?? currentDescriptor
        )
        if let descriptor {
            currentDescriptor = descriptor
        }
        if let model = coreModel, coreConfig == config {
            return model
        }
        let model = ManasMLXCore(config: config)
        coreModel = model
        coreConfig = config
        return model
    }

    static func makeCoreConfig(
        inputSize: Int,
        driveCount: Int,
        auxEnabled: Bool,
        descriptor: RobotDescriptor?
    ) -> ManasMLXCoreConfig {
        guard let descriptor else {
            return ManasMLXCoreConfig(
                inputSize: inputSize,
                embeddingSize: 128,
                fastHiddenSize: 256,
                slowHiddenSize: 128,
                driveCount: driveCount,
                driveScale: 1.0,
                auxSize: inputSize,
                auxEnabled: auxEnabled
            )
        }

        let typeLayout = buildTypeLayout(
            inputSize: inputSize,
            driveCount: driveCount,
            descriptor: descriptor
        )

        return ManasMLXCoreConfig(
            inputSize: inputSize,
            embeddingSize: 128,
            fastHiddenSize: 256,
            slowHiddenSize: 128,
            driveCount: driveCount,
            driveScale: 1.0,
            auxSize: inputSize,
            auxEnabled: auxEnabled,
            descendingSize: typeLayout.descendingTypeIndices.count,
            descendingEmbeddingSize: typeLayout.descendingTypeIndices.isEmpty ? 0 : 16,
            typeEmbeddingDim: 16,
            typeEmbeddingCount: typeLayout.typeCount,
            ascendingTypeIndices: typeLayout.ascendingTypeIndices,
            descendingTypeIndices: typeLayout.descendingTypeIndices.isEmpty ? nil : typeLayout.descendingTypeIndices,
            actuatorTypeIndices: typeLayout.driveTypeIndices,
            useSharedEncoder: true,
            useSharedDecoder: true,
            actuatorCount: driveCount
        )
    }

    private struct TypeLayout {
        let typeCount: Int
        let ascendingTypeIndices: [Int]
        let descendingTypeIndices: [Int]
        let driveTypeIndices: [Int]
    }

    private static func buildTypeLayout(
        inputSize: Int,
        driveCount: Int,
        descriptor: RobotDescriptor
    ) -> TypeLayout {
        var typeToIndex: [String: Int] = [:]
        var nextIndex = 0

        func resolve(_ type: String) -> Int {
            if let existing = typeToIndex[type] {
                return existing
            }
            typeToIndex[type] = nextIndex
            nextIndex += 1
            return nextIndex - 1
        }

        let ascendingTypeIndices = ascendingTypePattern(inputSize: inputSize, resolve: resolve)
        let descendingTypes = descriptorDescendingTypes(descriptor: descriptor)
        let descendingTypeIndices = descendingTypes.map(resolve)
        let driveTypes = descriptorDriveTypes(descriptor: descriptor, driveCount: driveCount)
        let driveTypeIndices = driveTypes.map(resolve)

        return TypeLayout(
            typeCount: nextIndex,
            ascendingTypeIndices: ascendingTypeIndices,
            descendingTypeIndices: descendingTypeIndices,
            driveTypeIndices: driveTypeIndices
        )
    }

    private static func descriptorDescendingTypes(descriptor: RobotDescriptor) -> [String] {
        guard let descendingChannels = descriptor.control.descendingChannels,
              !descendingChannels.isEmpty else {
            return []
        }

        let descendingSignalsByID = Dictionary(
            uniqueKeysWithValues: (descriptor.signals.descending ?? []).map { ($0.id, $0) }
        )

        return descendingChannels.map { id in
            if let definition = descendingSignalsByID[id] {
                let semantic = definition.group?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let semantic, !semantic.isEmpty {
                    return semantic
                }
                return definition.name
            }
            return id
        }
    }

    private static func descriptorDriveTypes(descriptor: RobotDescriptor, driveCount: Int) -> [String] {
        let driveSignalsByID = Dictionary(
            uniqueKeysWithValues: descriptor.signals.drive.map { ($0.id, $0) }
        )

        var types: [String] = []
        types.reserveCapacity(driveCount)

        for id in descriptor.control.driveChannels.prefix(driveCount) {
            if let definition = driveSignalsByID[id] {
                let semantic = definition.group?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let semantic, !semantic.isEmpty {
                    types.append(semantic)
                } else {
                    types.append(definition.name)
                }
            } else {
                types.append(id)
            }
        }

        while types.count < driveCount {
            types.append("drive_channel_\(types.count)")
        }
        return types
    }

    private static func ascendingTypePattern(
        inputSize: Int,
        resolve: (String) -> Int
    ) -> [Int] {
        guard inputSize > 0 else { return [] }

        // TrunkBundle is [energy..., phase..., quality..., spike...].
        // Prefer semantic type sharing across channels over per-index embeddings.
        if inputSize % 4 == 0 {
            let perBand = inputSize / 4
            var indices: [Int] = []
            indices.reserveCapacity(inputSize)
            indices.append(contentsOf: Array(repeating: resolve("trunk.energy"), count: perBand))
            indices.append(contentsOf: Array(repeating: resolve("trunk.phase"), count: perBand))
            indices.append(contentsOf: Array(repeating: resolve("trunk.quality"), count: perBand))
            indices.append(contentsOf: Array(repeating: resolve("trunk.spike"), count: perBand))
            return indices
        }

        return (0..<inputSize).map { resolve("trunk.channel.\($0)") }
    }

    private func prepareReflex(inputSize: Int, driveCount: Int) -> ManasMLXReflex {
        let config = ManasMLXReflexConfig(inputSize: inputSize, driveCount: driveCount)
        if let model = reflexModel, reflexConfig == config {
            return model
        }
        let model = ManasMLXReflex(config: config)
        reflexModel = model
        reflexConfig = config
        return model
    }

    private func loadTrainingDatasets(from root: URL) throws -> [ManasTrainingDataset] {
        let fileManager = FileManager.default
        let metaURL = root.appendingPathComponent("meta.json")
        let recordsURL = root.appendingPathComponent("records.jsonl")

        if fileManager.fileExists(atPath: metaURL.path) && fileManager.fileExists(atPath: recordsURL.path) {
            return [adaptDataset(try ManasTrainingDataset.load(from: root))]
        }

        let items = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let datasets = try items.compactMap { url -> ManasTrainingDataset? in
            let meta = url.appendingPathComponent("meta.json")
            let records = url.appendingPathComponent("records.jsonl")
            guard fileManager.fileExists(atPath: meta.path),
                  fileManager.fileExists(atPath: records.path) else {
                return nil
            }
            return adaptDataset(try ManasTrainingDataset.load(from: url))
        }
        guard !datasets.isEmpty else {
            throw ModelStoreError.noTrainingDatasetsFound
        }
        return datasets
    }

    private func adaptDataset(_ dataset: ManasTrainingDataset) -> ManasTrainingDataset {
        let observationMode = ManasMLXObservationMode.trainingMode(
            channelCount: dataset.metadata.channelCount,
            driveCount: dataset.metadata.driveCount
        )
        let records = dataset.records.map { record in
            ManasTrainingDatasetRecord(
                time: record.time,
                sensors: record.sensors.filter { observationMode.accepts(channelIndex: $0.channelIndex) },
                driveIntents: record.driveIntents,
                reflexCorrections: record.reflexCorrections,
                tiltRadians: record.tiltRadians,
                omegaMagnitude: record.omegaMagnitude,
                reward: record.reward,
                done: record.done,
                truncated: record.truncated,
                episodeId: record.episodeId,
                policyId: record.policyId
            )
        }
        let maxChannelIndex = records.flatMap(\.sensors).map { Int($0.channelIndex) }.max() ?? -1
        let metadata = ManasTrainingDatasetMetadata(
            schemaVersion: dataset.metadata.schemaVersion,
            scenarioId: dataset.metadata.scenarioId,
            seed: dataset.metadata.seed,
            timeStep: dataset.metadata.timeStep,
            determinismTier: dataset.metadata.determinismTier,
            configHash: dataset.metadata.configHash,
            channelCount: maxChannelIndex + 1,
            driveCount: dataset.metadata.driveCount,
            recordCount: dataset.metadata.recordCount,
            episodeId: dataset.metadata.episodeId,
            policyId: dataset.metadata.policyId,
            rewardSum: dataset.metadata.rewardSum,
            done: dataset.metadata.done,
            truncated: dataset.metadata.truncated,
            terminalReason: dataset.metadata.terminalReason
        )
        return ManasTrainingDataset(metadata: metadata, records: records)
    }

    private func buildTrainingPipeline(
        useQualityGating: Bool,
        observationMode: ManasMLXObservationMode
    ) -> ManasTrunkPipeline {
        let bundle = observationMode.makeBundle()
        let gate: any Gating = useQualityGating
            ? QualityGating(configuration: .init(minGate: 0.2, maxGate: 1.0))
            : IdentityGating()
        let trunks = BasicTrunksBuilder()
        return ManasTrunkPipeline(bundle: bundle, gate: gate, trunks: trunks)
    }

    private func cappedBatches<T>(_ batches: [T], limit: Int?, currentCount: Int) -> [T] {
        TrainingBatchLimiter(limit: limit, currentCount: currentCount).select(batches)
    }

    private func interleavedBatches<T>(_ groups: [[T]]) -> [T] {
        let maxCount = groups.map(\.count).max() ?? 0
        var result: [T] = []
        result.reserveCapacity(groups.reduce(0) { $0 + $1.count })
        for index in 0..<maxCount {
            for group in groups where index < group.count {
                result.append(group[index])
            }
        }
        return result
    }

    private func beginExclusive() throws {
        if isBusy {
            throw ModelStoreError.busy
        }
        isBusy = true
    }

    private func endExclusive() {
        isBusy = false
    }

    #if DEBUG
    func initializeModelsForTesting(
        inputSize: Int,
        driveCount: Int,
        auxEnabled: Bool,
        reflexInputSize: Int
    ) {
        _ = prepareCore(inputSize: inputSize, driveCount: driveCount, auxEnabled: auxEnabled)
        _ = prepareReflex(inputSize: reflexInputSize, driveCount: driveCount)
    }

    func holdExclusiveForTesting(control: SimulationControl) async throws {
        try beginExclusive()
        defer { endExclusive() }

        try await control.checkpoint()
    }
    #endif

}
