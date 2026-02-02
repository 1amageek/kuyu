import Foundation
import Logging
import kuyu
import simd

enum KuyuUIPreviewFactory {
    private static let previewOutput: KuyAtt1RunOutput = {
        let gains: ImuRateDampingCutGains
        do {
            gains = try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2, hoverThrustScale: 1.0)
        } catch {
            preconditionFailure("Invalid preview gains: \(error)")
        }

        let determinism: DeterminismConfig
        do {
            determinism = try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
        } catch {
            preconditionFailure("Invalid preview determinism: \(error)")
        }

        let request = SimulationRunRequest(
            gains: gains,
            cutPeriodSteps: 2,
            noise: .zero,
            determinism: determinism,
            learningMode: .off,
            modelDescriptorPath: KuyuUIModelPaths.defaultDescriptorPath(),
            overrideParameters: nil
        )

        let service = SimulationRunnerService()
        do {
            return try service.run(request: request)
        } catch {
            preconditionFailure("Preview simulation failed: \(error)")
        }
    }()

    @MainActor
    static func model() -> SimulationViewModel {
        let store = UILogStore(buffer: UILogBuffer())
        let model = SimulationViewModel(logStore: store)
        let output = previewOutput
        model.insertRun(runRecord(output: output))
        for entry in logEntries(output: output) {
            store.emit(entry)
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
        runRecord(output: previewOutput)
    }

    static func scenario() -> ScenarioRunRecord {
        runRecord(output: previewOutput).scenarios.first!
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

    static func logEntries() -> [UILogEntry] {
        logEntries(output: previewOutput)
    }

    static func samples() -> [MetricSample] {
        scenario().metrics.tiltDegrees
    }
}
