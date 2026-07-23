import Foundation
import Logging
import KuyuCore
import KuyuMLX
import KuyuPhysics
import KuyuScenarios
public enum KuyuUIPreviewFactory {
    private static func placeholderOutput() -> KuyAtt1RunOutput {
        do {
            return try makePlaceholderOutput()
        } catch {
            return emptyOutput()
        }
    }

    private static func makePlaceholderOutput() throws -> KuyAtt1RunOutput {
        let scenarioId = try ScenarioID("PREVIEW-SCN")
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
        let timeStep = try TimeStep(delta: 0.02)
        let determinism = DeterminismConfig.tier1Baseline
        let log = SimulationLog(
            scenarioId: scenarioId,
            seed: seed,
            timeStep: timeStep,
            determinism: determinism,
            configHash: "preview",
            events: []
        )
        let entry = ScenarioLogEntry(key: ScenarioKey(scenarioId: scenarioId, seed: seed), log: log)
        return KuyAtt1RunOutputFactory().makeEvaluationOnly(
            evaluations: [evaluation],
            logs: [entry],
            manifest: [],
            replaySkippedReason: "Preview fixtures do not execute simulations."
        )
    }

    private static func emptyOutput() -> KuyAtt1RunOutput {
        KuyAtt1RunOutputFactory().makeEvaluationOnly(
            evaluations: [],
            logs: [],
            manifest: [],
            replaySkippedReason: "Preview fixture construction failed."
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
        model.learningCampaignLiveFitnessSamples = [
            MetricSample(time: 1, value: 0.35),
            MetricSample(time: 2, value: 0.62),
            MetricSample(time: 3, value: 0.81)
        ]
        model.learningCampaignLiveTaskPassSamples = [
            MetricSample(time: 1, value: 0.33),
            MetricSample(time: 2, value: 0.67),
            MetricSample(time: 3, value: 1.0)
        ]
        model.learningCampaignLiveRewardSamples = [
            MetricSample(time: 1, value: -2.0),
            MetricSample(time: 2, value: 8.0),
            MetricSample(time: 3, value: 18.0)
        ]
        model.lastPostRegressionGate = makePreviewPostRegressionGate()
        for entry in logEntries(output: output) { store.emit(entry) }
        return model
    }

    private static func makePreviewPostRegressionGate() -> PostRegressionGateState? {
        do {
            let artifactDirectory = URL(fileURLWithPath: "/tmp/kuyu-preview/post-regression", isDirectory: true)
            let rolloutSuites = [
                ReferenceQuadrotorRegressionRolloutEntry(
                    suite: 6,
                    track: "longHorizonTask",
                    policyID: "preview-policy",
                    episodeCount: 1,
                    rewardSum: 63.656,
                    rewardAverage: 63.656,
                    doneCount: 1,
                    truncatedCount: 0,
                    failureCount: 0,
                    cancelledCount: 0,
                    failureReasons: [],
                    taskPassCount: 1,
                    taskFailureCount: 0,
                    taskFailureReasons: [],
                    taskQuality: [
                        ReferenceQuadrotorTaskQualitySummary(
                            task: "lift",
                            scenarioID: "PREVIEW-SCN",
                            seed: 1,
                            passed: true,
                            failureReasons: [],
                            evaluatorID: ReferenceQuadrotorRegressionQualityGatePolicy.qualityEvaluatorID,
                            targetZ: 1,
                            tolerance: 0.2,
                            warmupTime: 1,
                            requiredHoldTime: 2.0,
                            achievedHoldTime: 7.5,
                            maxAltitudeErrorAfterWarmup: 0,
                            maxVerticalVelocityAfterWarmup: 0
                        )
                    ],
                    workerSummaries: [
                        ReferenceQuadrotorRegressionWorkerSummary(
                            workerIndex: 0,
                            snapshotID: nil,
                            rolloutShardPath: nil,
                            episodeCount: 1,
                            rewardSum: 63.656,
                            rewardAverage: 63.656,
                            throughput: 0.33,
                            doneCount: 1,
                            truncatedCount: 0,
                            failureCount: 0,
                            cancelledCount: 0
                        )
                    ],
                    artifactPath: nil
                )
            ]
            return try ReferenceQuadrotorRegressionArtifactLoader().inspectionState(
                artifactDirectory: artifactDirectory,
                request: ReferenceQuadrotorRegressionInspectionRequest(
                    startedAt: Date(timeIntervalSince1970: 0),
                    controller: "manasMLX",
                    environmentController: "preview",
                    snapshot: nil,
                    preflightPassed: true,
                    preflightFailure: nil,
                    environmentReady: true,
                    environmentTasks: [],
                    rolloutPassed: true,
                    rolloutSuites: rolloutSuites,
                    failOnTruncation: false,
                    minimumRewardAverage: nil,
                    qualityGateTask: "lift"
                )
            )
        } catch {
            return nil
        }
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

    public static func scenario() -> ScenarioRunRecord? {
        runRecord().scenarios.first
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

    public static func logEntry() -> UILogEntry {
        logEntries(output: runRecord().output).first ?? UILogEntry(
            timestamp: Date(),
            level: .warning,
            label: "kuyu.ui",
            message: "Preview fixture unavailable",
            metadata: [:]
        )
    }

    public static func samples() -> [MetricSample] {
        scenario()?.metrics.tiltDegrees ?? []
    }
}
