import Foundation
import ManasCore
import ManasMLXModels
import ManasMLXTraining
import KuyuCore

@MainActor
public final class ManasMLXModelStore {
    private let lock = NSLock()
    private var coreModel: ManasMLXCore?
    private var coreConfig: ManasMLXCoreConfig?
    private var reflexModel: ManasMLXReflex?
    private var reflexConfig: ManasMLXReflexConfig?
    private var isBusy: Bool = false

    public init() {}

    public func runManasMLX(
        parameters: QuadrotorParameters,
        schedule: SimulationSchedule,
        request: SimulationRunRequest,
        control: SimulationControl?
    ) async throws -> KuyAtt1RunOutput {
        try beginExclusive()
        defer { endExclusive() }

        var bundle = Imu6NerveBundle(configuration: .init(
            gyroRange: -20...20,
            accelRange: -20...20,
            qualityFloor: 0.2
        ))
        var gate: any Gating = request.useQualityGating
            ? QualityGating(configuration: .init(minGate: 0.2, maxGate: 1.0))
            : IdentityGating()
        var trunks = BasicTrunksBuilder()
        let sizing = try ManasMLXCut.computeSizing(bundle: &bundle, gate: &gate, trunks: &trunks)

        let core = prepareCore(
            inputSize: sizing.trunkSize,
            driveCount: sizing.driveCount,
            auxEnabled: request.useAux
        )
        let reflex = prepareReflex(inputSize: sizing.fastTapCount, driveCount: sizing.driveCount)

        let runner = ScenarioRunner<ManasMLXCut, DirectExternalDAL>(
            parameters: parameters,
            schedule: schedule,
            determinism: request.determinism,
            noise: request.noise,
            hoverThrustScale: request.gains.hoverThrustScale
        )
        let suite = KuyAtt1Suite()
        let definitions = try suite.scenarios()
        let manifest = ScenarioManifestBuilder().build(from: definitions)

        var evaluations: [ScenarioEvaluation] = []
        let replayChecks: [ReplayCheckResult] = []
        var logs: [ScenarioLogEntry] = []

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
                externalDal: DirectExternalDAL(),
                control: control
            )
            let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
            logs.append(ScenarioLogEntry(key: key, log: log))

            let evaluation = ScenarioEvaluator().evaluate(definition: definition, log: log)
            evaluations.append(evaluation)
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

        return KuyAtt1RunOutput(result: result, summary: summary, logs: logs)
    }

    public func trainCore(
        datasetURL: URL,
        sequenceLength: Int,
        learningRate: Double,
        epochs: Int,
        useAux: Bool,
        useQualityGating: Bool
    ) throws -> TrainingResult {
        try beginExclusive()
        defer { endExclusive() }

        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let maxBatches = isPreview ? 8 : nil

        let datasets = try loadTrainingDatasets(from: datasetURL)
        let driveCount = datasets.first?.metadata.driveCount ?? 0
        guard driveCount > 0 else {
            throw NSError(domain: "kuyu.ui", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid drive count"])
        }

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
        if useAux {
            losses = try ManasMLXTrainer.trainCoreWithAux(
                model: core,
                batches: allAuxBatches,
                config: trainConfig
            )
        } else {
            losses = ManasMLXTrainer.trainCoreSupervised(
                model: core,
                batches: allBatches,
                config: trainConfig
            )
        }

        return TrainingResult(finalLoss: Double(losses.last ?? 0), epochs: epochs)
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
            accelRange: -20...20,
            qualityFloor: 0.2
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
