import Foundation
import KuyuCore
import KuyuMLX
import KuyuProfiles

public struct TrainingLoopConfig: Sendable, Equatable {
    var maxIterations: Int
    var evaluationInterval: Int
    var stopOnPass: Bool
    var patience: Int
    var minDelta: Double
    var maxConsecutiveFailures: Int
    var allowAutoBackoff: Bool
    var enableDatasetExport: Bool
    var enableTraining: Bool
}

public enum TrainingLoopEvent: Sendable, Equatable {
    case started
    case iterationStarted(Int)
    case runStarted(iteration: Int)
    case runCompleted(iteration: Int, output: KuyAtt1RunOutput, score: Double)
    case teacherRunStarted(iteration: Int, hoverThrustScale: Double)
    case teacherRunCompleted(iteration: Int, output: KuyAtt1RunOutput)
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

public struct TrainingLoopSummary: Sendable, Equatable {
    let iterations: Int
    let bestScore: Double
    let lastScore: Double
    let passed: Bool
    let failures: [String]
}

@MainActor
public final class TrainingLoopController {
    private let lock = NSLock()
    private let runnerService: SimulationRunnerService
    private let trainingService: TrainingService
    private let datasetExporter: TrainingDatasetExporter

    private var loopControl = SimulationControl()
    private var currentSimulationControl: SimulationControl?
    private var task: Task<Void, Never>?
    private var telemetry: ((WorldStepLog) -> Void)?

    private func explorationHoverThrustScale(iteration: Int) -> Double {
        let schedule: [Double] = [0.7, 1.3, 0.85, 1.15, 0.95, 1.05, 1.0]
        if iteration <= schedule.count {
            return schedule[max(iteration - 1, 0)]
        }
        let amplitude = max(0.02, 0.1 * pow(0.7, Double(iteration - schedule.count)))
        return 1.0 + (iteration % 2 == 0 ? -amplitude : amplitude)
    }

    public init(
        modelStore: ManasMLXModelStore,
        runnerService: SimulationRunnerService? = nil,
        trainingService: TrainingService? = nil,
        datasetExporter: TrainingDatasetExporter = TrainingDatasetExporter()
    ) {
        self.runnerService = runnerService ?? SimulationRunnerService(modelStore: modelStore)
        self.trainingService = trainingService ?? TrainingService(modelStore: modelStore)
        self.datasetExporter = datasetExporter
    }

    public func setTelemetry(_ handler: ((WorldStepLog) -> Void)?) {
        telemetry = handler
    }

    public func start(
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

    public func pause() async {
        let (loop, current) = withLock { (loopControl, currentSimulationControl) }
        await loop.requestPause()
        if let current {
            await current.requestPause()
        }
    }

    public func resume() async {
        let (loop, current) = withLock { (loopControl, currentSimulationControl) }
        await loop.requestResume()
        if let current {
            await current.requestResume()
        }
    }

    public func stop() async {
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
                output = try await runnerService.run(
                    request: runRequest,
                    control: simControl,
                    telemetry: telemetry
                )
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
            await Task.yield()

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

            let useTeacher = runRequest.taskMode == .singleLift && (config.enableDatasetExport || config.enableTraining)
            var datasetOutput = output
            if useTeacher {
                do {
                    try await control.checkpoint()
                    let hoverScale = explorationHoverThrustScale(iteration: iteration)
                    onEvent(.teacherRunStarted(iteration: iteration, hoverThrustScale: hoverScale))
                    let teacherGains = try ImuRateDampingCutGains(
                        kp: runRequest.gains.kp,
                        kd: runRequest.gains.kd,
                        yawDamping: runRequest.gains.yawDamping,
                        hoverThrustScale: hoverScale
                    )
                    let teacherRequest = SimulationRunRequest(
                        controller: .baseline,
                        taskMode: runRequest.taskMode,
                        gains: teacherGains,
                        cutPeriodSteps: runRequest.cutPeriodSteps,
                        noise: runRequest.noise,
                        determinism: runRequest.determinism,
                        modelDescriptorPath: runRequest.modelDescriptorPath,
                        overrideParameters: runRequest.overrideParameters,
                        useAux: runRequest.useAux,
                        useQualityGating: runRequest.useQualityGating
                    )
                    datasetOutput = try await runnerService.run(
                        request: teacherRequest,
                        control: SimulationControl(),
                        telemetry: telemetry
                    )
                    onEvent(.teacherRunCompleted(iteration: iteration, output: datasetOutput))
                } catch {
                    failures.append("iteration \(iteration) teacher run failed: \(error)")
                    onEvent(.failed(message: "Teacher run failed: \(error)"))
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
            }

            let iterationDir = datasetRoot.appendingPathComponent("iter-\(iteration)", isDirectory: true)
            if config.enableDatasetExport {
                do {
                    onEvent(.datasetExportStarted(iteration: iteration, path: iterationDir.path))
                    let outputs = try datasetExporter.write(output: datasetOutput, to: iterationDir)
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
            }

            if config.enableTraining {
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
