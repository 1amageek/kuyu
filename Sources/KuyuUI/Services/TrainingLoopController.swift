import Foundation
import KuyuCore
import KuyuMLX

struct TrainingLoopConfig: Sendable, Equatable {
    var maxIterations: Int
    var evaluationInterval: Int
    var stopOnPass: Bool
    var patience: Int
    var minDelta: Double
    var maxConsecutiveFailures: Int
    var allowAutoBackoff: Bool
}

enum TrainingLoopEvent: Sendable, Equatable {
    case started
    case iterationStarted(Int)
    case runStarted(iteration: Int)
    case runCompleted(iteration: Int, output: KuyAtt1RunOutput, score: Double)
    case datasetExportStarted(iteration: Int, path: String)
    case datasetExportCompleted(iteration: Int, count: Int)
    case trainingStarted(iteration: Int, path: String, epochs: Int, learningRate: Double)
    case trainingCompleted(iteration: Int, result: TrainingResult)
    case backoffApplied(newLearningRate: Double)
    case paused
    case resumed
    case stopped
    case completed(summary: TrainingLoopSummary)
    case failed(message: String)
}

struct TrainingLoopSummary: Sendable, Equatable {
    let iterations: Int
    let bestScore: Double
    let lastScore: Double
    let passed: Bool
    let failures: [String]
}

@MainActor
final class TrainingLoopController {
    private let lock = NSLock()
    private let runnerService: SimulationRunnerService
    private let trainingService: TrainingService
    private let datasetExporter: TrainingDatasetExporter

    private var loopControl = SimulationControl()
    private var currentSimulationControl: SimulationControl?
    private var task: Task<Void, Never>?

    init(
        modelStore: ManasMLXModelStore,
        runnerService: SimulationRunnerService? = nil,
        trainingService: TrainingService? = nil,
        datasetExporter: TrainingDatasetExporter = TrainingDatasetExporter()
    ) {
        self.runnerService = runnerService ?? SimulationRunnerService(modelStore: modelStore)
        self.trainingService = trainingService ?? TrainingService(modelStore: modelStore)
        self.datasetExporter = datasetExporter
    }

    func start(
        config: TrainingLoopConfig,
        runRequest: SimulationRunRequest,
        trainingTemplate: TrainingRequest,
        datasetRoot: URL,
        onEvent: @Sendable @escaping (TrainingLoopEvent) -> Void
    ) {
        let control: SimulationControl? = withLock {
            guard task == nil else { return nil }
            loopControl = SimulationControl()
            let control = loopControl
            task = Task { [weak self] in
                await self?.runLoop(
                    config: config,
                    runRequest: runRequest,
                    trainingTemplate: trainingTemplate,
                    datasetRoot: datasetRoot,
                    control: control,
                    onEvent: onEvent
                )
                self?.withLock {
                    self?.task = nil
                }
            }
            return control
        }
        _ = control
    }

    func pause() async {
        let (loop, current) = withLock { (loopControl, currentSimulationControl) }
        await loop.requestPause()
        if let current {
            await current.requestPause()
        }
    }

    func resume() async {
        let (loop, current) = withLock { (loopControl, currentSimulationControl) }
        await loop.requestResume()
        if let current {
            await current.requestResume()
        }
    }

    func stop() async {
        let (loop, current) = withLock { (loopControl, currentSimulationControl) }
        await loop.requestStop()
        if let current {
            await current.requestStop()
        }
    }

    private func runLoop(
        config: TrainingLoopConfig,
        runRequest: SimulationRunRequest,
        trainingTemplate: TrainingRequest,
        datasetRoot: URL,
        control: SimulationControl,
        onEvent: @Sendable (TrainingLoopEvent) -> Void
    ) async {
        onEvent(.started)
        var failures: [String] = []
        var consecutiveFailures = 0
        var remainingPatience = max(0, config.patience)
        var bestScore = -Double.greatestFiniteMagnitude
        var lastScore = bestScore
        var lastLoss: Double?
        var currentLearningRate = trainingTemplate.learningRate

        for iteration in 1...max(1, config.maxIterations) {
            do {
                try await control.checkpoint()
            } catch {
                onEvent(.stopped)
                return
            }

            onEvent(.iterationStarted(iteration))

            let simControl = SimulationControl()
            withLock { currentSimulationControl = simControl }
            let output: KuyAtt1RunOutput
            do {
                onEvent(.runStarted(iteration: iteration))
                output = try await runnerService.run(request: runRequest, control: simControl)
            } catch {
                withLock { currentSimulationControl = nil }
                consecutiveFailures += 1
                failures.append("iteration \(iteration) run failed: \(error)")
                onEvent(.failed(message: "Run failed: \(error)"))
                if consecutiveFailures >= config.maxConsecutiveFailures {
                    onEvent(.completed(summary: TrainingLoopSummary(
                        iterations: iteration,
                        bestScore: bestScore,
                        lastScore: lastScore,
                        passed: false,
                        failures: failures
                    )))
                    return
                }
                continue
            }
            withLock { currentSimulationControl = nil }
            consecutiveFailures = 0

            let score = score(from: output.summary)
            lastScore = score
            onEvent(.runCompleted(iteration: iteration, output: output, score: score))

            let shouldEvaluate = config.evaluationInterval > 0 ? (iteration % config.evaluationInterval == 0) : true
            if shouldEvaluate {
                if score > bestScore + config.minDelta {
                    bestScore = score
                    remainingPatience = max(0, config.patience)
                } else if remainingPatience > 0 {
                    remainingPatience -= 1
                }

                if config.stopOnPass, output.summary.suitePassed {
                    onEvent(.completed(summary: TrainingLoopSummary(
                        iterations: iteration,
                        bestScore: bestScore,
                        lastScore: lastScore,
                        passed: true,
                        failures: failures
                    )))
                    return
                }

                if remainingPatience == 0, config.patience > 0 {
                    onEvent(.completed(summary: TrainingLoopSummary(
                        iterations: iteration,
                        bestScore: bestScore,
                        lastScore: lastScore,
                        passed: output.summary.suitePassed,
                        failures: failures
                    )))
                    return
                }
            }

            let iterationDir = datasetRoot.appendingPathComponent("iter-\(iteration)", isDirectory: true)
            do {
                onEvent(.datasetExportStarted(iteration: iteration, path: iterationDir.path))
                let outputs = try datasetExporter.write(output: output, to: iterationDir)
                onEvent(.datasetExportCompleted(iteration: iteration, count: outputs.count))
            } catch {
                failures.append("iteration \(iteration) dataset export failed: \(error)")
                onEvent(.failed(message: "Dataset export failed: \(error)"))
                consecutiveFailures += 1
                if consecutiveFailures >= config.maxConsecutiveFailures {
                    onEvent(.completed(summary: TrainingLoopSummary(
                        iterations: iteration,
                        bestScore: bestScore,
                        lastScore: lastScore,
                        passed: false,
                        failures: failures
                    )))
                    return
                }
                continue
            }

            do {
                var trainingRequest = trainingTemplate
                trainingRequest = TrainingRequest(
                    datasetURL: iterationDir,
                    sequenceLength: trainingTemplate.sequenceLength,
                    epochs: trainingTemplate.epochs,
                    learningRate: currentLearningRate,
                    useAux: trainingTemplate.useAux,
                    useQualityGating: trainingTemplate.useQualityGating
                )
                onEvent(.trainingStarted(
                    iteration: iteration,
                    path: iterationDir.path,
                    epochs: trainingRequest.epochs,
                    learningRate: trainingRequest.learningRate
                ))
                let result = try await trainingService.trainCore(request: trainingRequest)
                onEvent(.trainingCompleted(iteration: iteration, result: result))

                if config.allowAutoBackoff, let lastLoss, result.finalLoss > lastLoss {
                    currentLearningRate = max(1e-6, currentLearningRate * 0.5)
                    onEvent(.backoffApplied(newLearningRate: currentLearningRate))
                }
                lastLoss = result.finalLoss
            } catch {
                failures.append("iteration \(iteration) training failed: \(error)")
                onEvent(.failed(message: "Training failed: \(error)"))
                consecutiveFailures += 1
                if consecutiveFailures >= config.maxConsecutiveFailures {
                    onEvent(.completed(summary: TrainingLoopSummary(
                        iterations: iteration,
                        bestScore: bestScore,
                        lastScore: lastScore,
                        passed: false,
                        failures: failures
                    )))
                    return
                }
            }
        }

        onEvent(.completed(summary: TrainingLoopSummary(
            iterations: config.maxIterations,
            bestScore: bestScore,
            lastScore: lastScore,
            passed: bestScore > 0,
            failures: failures
        )))
    }

    private func score(from summary: ValidationSummary) -> Double {
        var score = summary.suitePassed ? 1.0 : 0.0
        if let worstOvershoot = summary.aggregate.worstOvershootDegrees {
            score -= min(1.0, worstOvershoot / 90.0) * 0.4
        }
        if let recovery = summary.aggregate.averageRecoveryTime {
            score -= min(1.0, recovery / 5.0) * 0.3
        }
        if let hf = summary.aggregate.averageHfStabilityScore {
            score += max(0.0, min(hf, 1.0)) * 0.2
        }
        return score
    }

    @discardableResult
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
