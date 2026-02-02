import Configuration
import Foundation
import Logging
import Observation
import kuyu

@Observable
@MainActor
final class SimulationViewModel {
    private(set) var runs: [RunRecord] = []
    var selectedRunID: UUID?
    var selectedScenarioKey: ScenarioKey?
    var isRunning = false
    var runError: String?

    var kp: Double = 2.0
    var kd: Double = 0.25
    var yawDamping: Double = 0.2
    var hoverThrustScale: Double = 1.0
    var cutPeriodSteps: UInt64 = 2
    var determinismSelection: DeterminismSelection = .tier1
    var learningMode: LearningMode = .off

    var useEnvironmentConfig = false
    var logLevel: LogLevelOption = .info
    var logLabel: String = "kuyu.ui"
    var logDirectory: String = ""
    var modelDescriptorPath: String = KuyuUIModelPaths.defaultDescriptorPath()

    let logStore: UILogStore
    private let runnerService: SimulationRunnerService
    private var logger: Logger

    init(logStore: UILogStore, runnerService: SimulationRunnerService = SimulationRunnerService()) {
        self.logStore = logStore
        self.runnerService = runnerService
        self.logger = Logger(label: "kuyu.ui")
        self.logger.logLevel = .info
    }

    var selectedRun: RunRecord? {
        guard let selectedRunID else { return runs.first }
        return runs.first { $0.id == selectedRunID }
    }

    var selectedScenario: ScenarioRunRecord? {
        guard let run = selectedRun else { return nil }
        if let selectedScenarioKey {
            return run.scenarios.first { $0.id == selectedScenarioKey }
        }
        return run.scenarios.first
    }

    func applyEnvironmentConfig() {
        let config = KuyukaiConfigLoader().loadFromEnvironment()
        logLevel = LogLevelOption.from(level: config.logLevel)
        logLabel = config.logLabel
        logDirectory = config.logDirectory ?? ""
        refreshLogger()
    }

    func refreshLogger() {
        var updated = Logger(label: logLabel)
        updated.logLevel = effectiveLogLevel(logLevel.level)
        logger = updated
    }

    func runBaseline() {
        guard !isRunning else {
            emitTerminal(level: .warning, message: "Run already in progress")
            return
        }
        runError = nil
        isRunning = true

        let gains: ImuRateDampingCutGains
        do {
            gains = try ImuRateDampingCutGains(
                kp: kp,
                kd: kd,
                yawDamping: yawDamping,
                hoverThrustScale: hoverThrustScale
            )
        } catch {
            isRunning = false
            emitError("Invalid gains", error: error)
            return
        }

        let determinism: DeterminismConfig
        do {
            determinism = try determinismSelection.makeConfig()
        } catch {
            isRunning = false
            emitError("Invalid determinism config", error: error)
            return
        }

        let request = SimulationRunRequest(
            gains: gains,
            cutPeriodSteps: cutPeriodSteps,
            noise: .zero,
            determinism: determinism,
            learningMode: learningMode,
            modelDescriptorPath: resolvedDescriptorPath(),
            overrideParameters: preflightParameters()
        )

        emitTerminal(
            level: .notice,
            message: "Run started",
            metadata: [
                "tier": "\(determinism.tier)",
                "cutPeriod": "\(cutPeriodSteps)",
                "learning": learningMode.rawValue
            ]
        )

        let service = runnerService
        Task(priority: .userInitiated) { [request, service] in
            do {
                let output = try await Self.runInBackground(request: request, service: service)
                let record = Self.buildRunRecord(output: output)
                self.isRunning = false
                self.runs.insert(record, at: 0)
                self.selectedRunID = record.id
                self.selectedScenarioKey = record.scenarios.first?.id
                self.emitTerminal(
                    level: .info,
                    message: "Run completed",
                    metadata: [
                        "passed": "\(record.output.summary.suitePassed)"
                    ]
                )
                if !record.output.summary.suitePassed {
                    self.emitFailureDetails(output: record.output)
                }
            } catch {
                self.isRunning = false
                self.emitError("Run failed", error: error)
            }
        }
    }

    func exportLogs() {
        guard let run = selectedRun else { return }
        let trimmed = logDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            emitError("Log directory is empty")
            return
        }
        let url = URL(fileURLWithPath: trimmed, isDirectory: true)
        do {
            let bundle = try KuyAtt1LogWriter().write(output: run.output, to: url)
            emitTerminal(
                level: .info,
                message: "Logs exported",
                metadata: [
                    "path": "\(url.path)",
                    "count": "\(bundle.logs.count)"
                ]
            )
        } catch {
            emitError("Export failed", error: error)
        }
    }

    func clearRuns() {
        runs.removeAll()
        selectedRunID = nil
        selectedScenarioKey = nil
        runError = nil
    }

    func insertRun(_ run: RunRecord) {
        runs.insert(run, at: 0)
        selectedRunID = run.id
        selectedScenarioKey = run.scenarios.first?.id
    }

    func setModelDescriptorPath(_ path: String, source: String) {
        modelDescriptorPath = path
        emitTerminal(level: .info, message: "Model descriptor set", metadata: [
            "source": source,
            "path": path
        ])
    }

    private static func buildRunRecord(output: KuyAtt1RunOutput) -> RunRecord {
        let evaluationsByKey = Dictionary(
            uniqueKeysWithValues: output.result.evaluations.map {
                (ScenarioKey(scenarioId: $0.scenarioId, seed: $0.seed), $0)
            }
        )

        let scenarios: [ScenarioRunRecord] = output.logs.compactMap { entry in
            guard let evaluation = evaluationsByKey[entry.key] else { return nil }
            let metrics = ScenarioMetricsBuilder.build(log: entry.log)
            return ScenarioRunRecord(
                id: entry.key,
                evaluation: evaluation,
                log: entry.log,
                metrics: metrics
            )
        }.sorted { lhs, rhs in
            if lhs.id.scenarioId.rawValue == rhs.id.scenarioId.rawValue {
                return lhs.id.seed.rawValue < rhs.id.seed.rawValue
            }
            return lhs.id.scenarioId.rawValue < rhs.id.scenarioId.rawValue
        }

        return RunRecord(output: output, scenarios: scenarios)
    }

    private static func runInBackground(
        request: SimulationRunRequest,
        service: SimulationRunnerService
    ) async throws -> KuyAtt1RunOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let output = try service.run(request: request)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func emitError(_ message: String, error: Error? = nil) {
        let detail: String
        if let error {
            detail = "\(message): \(error)"
        } else {
            detail = message
        }
        runError = detail
        emitTerminal(level: .error, message: detail)
    }

    private func effectiveLogLevel(_ level: Logger.Level) -> Logger.Level {
        let order: [Logger.Level] = [.trace, .debug, .info, .notice, .warning, .error, .critical]
        guard let levelIndex = order.firstIndex(of: level),
              let errorIndex = order.firstIndex(of: .error) else {
            return level
        }
        return levelIndex > errorIndex ? .error : level
    }

    private func resolvedDescriptorPath() -> String {
        let resolved = KuyuUIModelPaths.resolveDescriptorPath(modelDescriptorPath)
        if resolved != modelDescriptorPath {
            modelDescriptorPath = resolved
            emitTerminal(level: .warning, message: "Model descriptor not found, using fallback", metadata: [
                "path": resolved
            ])
        }
        return resolved
    }

    private func preflightParameters() -> QuadrotorParameters? {
        let path = resolvedDescriptorPath()
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        do {
            let loader = RobotModelLoader()
            let loaded = try loader.loadDescriptor(path: trimmed)
            let parameters = try loader.loadQuadrotorParameters(descriptor: loaded)
            emitTerminal(level: .info, message: "Model loaded", metadata: [
                "path": trimmed
            ])
            return parameters
        } catch {
            emitTerminal(level: .warning, message: "Model load failed, using baseline", metadata: [
                "error": "\(error)"
            ])
            return QuadrotorParameters.baseline
        }
    }

    func emitTerminal(
        level: Logger.Level,
        message: String,
        metadata: [String: String] = [:]
    ) {
        let entry = UILogEntry(
            timestamp: Date(),
            level: level,
            label: logLabel,
            message: message,
            metadata: metadata
        )
        logStore.emit(entry)
    }

    private func emitFailureDetails(output: KuyAtt1RunOutput) {
        let failures = output.result.evaluations.filter { !$0.passed }
        if failures.isEmpty { return }

        emitTerminal(level: .warning, message: "Scenario failures", metadata: [
            "count": "\(failures.count)"
        ])

        for evaluation in failures {
            let reason = evaluation.failures.isEmpty ? "safety envelope violation" : evaluation.failures.joined(separator: ", ")
            emitTerminal(level: .warning, message: evaluation.scenarioId.rawValue, metadata: [
                "seed": "\(evaluation.seed.rawValue)",
                "reason": reason,
                "maxTilt": String(format: "%.2f", evaluation.maxTiltDegrees),
                "maxOmega": String(format: "%.2f", evaluation.maxOmega),
                "sustained": String(format: "%.3f", evaluation.sustainedViolationSeconds)
            ])
        }
    }
}
