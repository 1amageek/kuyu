import Foundation
import Logging
import KuyuCore
import KuyuPhysics
import KuyuScenarios
public enum KuyuUIPreviewFactory {
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
            controller: .teacherBaseline,
            gains: gains,
            cutPeriodSteps: 2,
            noise: .zero,
            determinism: determinism,
            robotManifestPath: KuyuUIModelPaths.defaultRobotManifestPath(),
            overrideParameters: nil,
            useAux: true,
            useQualityGating: true
        )
    }

    @MainActor
    public static func model() -> SimulationViewModel {
        let store = UILogStore(buffer: UILogBuffer())
        let model = SimulationViewModel(
            logStore: store,
            prepareStarterProjectOnInit: false
        )
        let output = placeholderOutput()
        model.insertRun(runRecord(output: output))
        model.trainingLossSamples = [
            MetricSample(time: 1, value: 0.42),
            MetricSample(time: 2, value: 0.24),
            MetricSample(time: 3, value: 0.12)
        ]
        model.validationLossSamples = [
            MetricSample(time: 1, value: 0.48),
            MetricSample(time: 2, value: 0.28),
            MetricSample(time: 3, value: 0.16)
        ]
        model.loopScoreSamples = [
            MetricSample(time: 1, value: 0.35),
            MetricSample(time: 2, value: 0.62),
            MetricSample(time: 3, value: 0.81)
        ]
        model.passRateSamples = [
            MetricSample(time: 1, value: 0.33),
            MetricSample(time: 2, value: 0.67),
            MetricSample(time: 3, value: 1.0)
        ]
        model.failureRateSamples = [
            MetricSample(time: 1, value: 0.67),
            MetricSample(time: 2, value: 0.33),
            MetricSample(time: 3, value: 0.0)
        ]
        model.safetyViolationSamples = [
            MetricSample(time: 1, value: 0.12),
            MetricSample(time: 2, value: 0.04),
            MetricSample(time: 3, value: 0.0)
        ]
        model.rewardAverageSamples = [
            MetricSample(time: 1, value: -2.0),
            MetricSample(time: 2, value: 8.0),
            MetricSample(time: 3, value: 18.0)
        ]
        model.workerThroughputSamples = [
            MetricSample(time: 1, value: 12),
            MetricSample(time: 2, value: 14),
            MetricSample(time: 3, value: 15)
        ]
        model.trainingLiveStatus = TrainingLiveStatus(
            phase: .evaluating,
            message: "Suite passed",
            iteration: 3,
            datasetPath: "/tmp/kuyu-preview",
            datasetCount: 3,
            epochs: 4,
            learningRate: 0.001,
            passRate: 1.0,
            failureRate: 0.0,
            safetyViolationSeconds: 0.0,
            lastRunPassed: true,
            convergenceAccepted: true,
            convergenceReason: "accepted",
            plateauDetected: false,
            overfitRiskDetected: false,
            safetyRegressionDetected: false,
            checkpointState: "accepted",
            checkpointReason: "accepted",
            bestCheckpointID: "preview-checkpoint",
            artifactDirectoryPath: "/tmp/kuyu-preview"
        )
        model.lastPostRegressionGate = PostRegressionGateState(
            artifactDirectory: URL(fileURLWithPath: "/tmp/kuyu-preview/post-regression", isDirectory: true),
            accepted: true,
            qualityTask: "lift",
            rolloutCount: 1,
            episodeCount: 1,
            rewardAverage: 63.656,
            taskPassRate: 1.0,
            achievedHoldTime: 7.5,
            requiredHoldTime: 2.0,
            minimumHoldTimeRatio: 3.75,
            maxAltitudeErrorAfterWarmup: 0.0,
            tolerance: 0.2,
            maximumAltitudeErrorRatio: 0.0,
            worstTrack: "longHorizonTask",
            worstScenarioID: "PREVIEW-SCN",
            minimumWorkerThroughput: 0.33,
            rejectReasons: []
        )
        model.trainingTimeline = [
            TrainingTimelineEntry(phase: .evaluating, message: "Suite passed", iteration: 3),
            TrainingTimelineEntry(phase: .supervisedTraining, message: "Training completed", iteration: 3),
            TrainingTimelineEntry(phase: .datasetExport, message: "Dataset exported", iteration: 3),
            TrainingTimelineEntry(phase: .rollout, message: "Policy rollout", iteration: 3)
        ]
        for entry in logEntries(output: output) { store.emit(entry) }
        return model
    }

    public static func runRecord(output: KuyAtt1RunOutput) -> RunRecord {
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

    public static func runRecord() -> RunRecord {
        runRecord(output: placeholderOutput())
    }

    public static func scenario() -> ScenarioRunRecord {
        runRecord().scenarios.first!
    }

    public static func logEntries(output: KuyAtt1RunOutput) -> [UILogEntry] {
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

    public static func samples() -> [MetricSample] {
        scenario().metrics.tiltDegrees
    }
}
