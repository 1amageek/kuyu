import Foundation
import Logging
import KuyuCore
import KuyuMLX

enum KuyuUIPreviewFactory {
    private static func placeholderOutput() -> KuyAtt1RunOutput {
        let scenarioId = try! ScenarioID("PREVIEW-SCN")
        let seed = ScenarioSeed(1)
        let evaluation = ScenarioEvaluation(
            scenarioId: scenarioId,
            seed: seed,
            passed: true,
            maxOmega: 0,
            maxTiltDegrees: 0,
            sustainedViolationSeconds: 0,
            recoveryTimeSeconds: nil,
            overshootDegrees: nil,
            hfStabilityScore: nil,
            failures: []
        )
        let result = SuiteRunResult(evaluations: [evaluation], replayChecks: [], passed: true)
        let aggregate = EvaluationAggregate.from(evaluations: [evaluation])
        let summary = ValidationSummary(
            suitePassed: true,
            evaluations: [evaluation],
            replayChecks: [],
            manifest: [],
            aggregate: aggregate
        )
        let timeStep = try! TimeStep(delta: 0.02)
        let determinism = try! DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
        let log = SimulationLog(
            scenarioId: scenarioId,
            seed: seed,
            timeStep: timeStep,
            determinism: determinism,
            configHash: "preview",
            events: []
        )
        let entry = ScenarioLogEntry(key: ScenarioKey(scenarioId: scenarioId, seed: seed), log: log)
        return KuyAtt1RunOutput(result: result, summary: summary, logs: [entry])
    }

    private static func placeholderRequest() -> SimulationRunRequest {
        let gains = try! ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2, hoverThrustScale: 1.0)
        let determinism = try! DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
        return SimulationRunRequest(
            controller: .baseline,
            gains: gains,
            cutPeriodSteps: 2,
            noise: .zero,
            determinism: determinism,
            modelDescriptorPath: KuyuUIModelPaths.defaultDescriptorPath(),
            overrideParameters: nil,
            useAux: true,
            useQualityGating: true
        )
    }

    @MainActor
    static func model() -> SimulationViewModel {
        let store = UILogStore(buffer: UILogBuffer())
        let model = SimulationViewModel(logStore: store)
        let output = placeholderOutput()
        model.insertRun(runRecord(output: output))
        for entry in logEntries(output: output) { store.emit(entry) }

        let request = placeholderRequest()
        Task {
            let service = SimulationRunnerService(modelStore: ManasMLXModelStore())
            do {
                let output = try await service.run(request: request)
                model.insertRun(runRecord(output: output))
                for entry in logEntries(output: output) { store.emit(entry) }
            } catch {
                store.emit(UILogEntry(
                    timestamp: Date(),
                    level: .error,
                    label: "kuyu.ui",
                    message: "Preview run failed",
                    metadata: ["error": "\(error)"]
                ))
            }
        }
        return model
    }

    static func runRecord(output: KuyAtt1RunOutput) -> RunRecord {
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

    static func runRecord() -> RunRecord {
        runRecord(output: placeholderOutput())
    }

    static func scenario() -> ScenarioRunRecord {
        runRecord().scenarios.first!
    }

    static func logEntries(output: KuyAtt1RunOutput) -> [UILogEntry] {
        let tier = output.logs.first?.log.determinism.tier.rawValue ?? "unknown"
        return [
            UILogEntry(
                timestamp: Date(),
                level: .notice,
                label: "kuyu.ui",
                message: "Run started",
                metadata: ["tier": tier, "cutPeriod": "2"]
            ),
            UILogEntry(
                timestamp: Date(),
                level: .info,
                label: "kuyu.ui",
                message: "Run completed",
                metadata: ["passed": "\(output.summary.suitePassed)"]
            )
        ]
    }

    static func samples() -> [MetricSample] {
        scenario().metrics.tiltDegrees
    }
}