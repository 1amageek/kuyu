import Foundation
import KuyuMLXCampaignContracts
import KuyuTraining
import SwiftUI

extension KuyuUIPreviewFactory {
    @MainActor
    public static func learningCampaignActivityView() -> AnyView {
        do {
            let model = try learningCampaignActivityModel()
            return AnyView(
                ScrollView {
                    LearningCampaignActivityView(model: model)
                        .frame(maxWidth: 760)
                        .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            )
        } catch {
            return AnyView(ContentUnavailableView(
                "Activity Preview Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(String(describing: error))
            ))
        }
    }

    @MainActor
    private static func learningCampaignActivityModel() throws -> SimulationViewModel {
        let model = model()
        let now = Date()
        let artifactRoot = URL(
            fileURLWithPath: "/tmp/kuyu-preview/learning-campaign",
            isDirectory: true
        )
        let progressEvents = try learningCampaignActivityEvents(now: now)
        model.isLearningCampaignRunning = true
        model.learningCampaignMonitorEnabled = true
        model.learningCampaignArtifactDirectory = artifactRoot.path
        model.learningCampaignLastRunnerEventAt = now.addingTimeInterval(-0.5)
        model.learningCampaignLastArtifactLoadStartedAt = now.addingTimeInterval(-0.4)
        model.learningCampaignLastArtifactLoadFinishedAt = now.addingTimeInterval(-0.3)
        model.learningCampaignLastArtifactLoadChangedAt = now.addingTimeInterval(-0.3)
        model.learningCampaignState = LearningCampaignRunStoreState(
            artifactDirectory: artifactRoot,
            plan: learningCampaignActivityPlan(artifactRoot: artifactRoot),
            status: nil,
            summary: nil,
            validation: nil,
            retention: nil,
            accelerator: nil,
            progressEvents: progressEvents,
            generations: [],
            candidates: [],
            vectorizedBatches: [
                LearningCampaignVectorizedBatchState(
                    kind: .evaluation,
                    seed: "seed-1",
                    generationIndex: 2,
                    candidateCount: 24,
                    completedCandidateCount: 12,
                    elapsedSeconds: 0.84,
                    acceleratorDevice: "gpu",
                    policyExecutionMode: "mlx-stacked",
                    observationExecutionMode: "tensor",
                    worldExecutionMode: "tensor-world",
                    actionEncoding: "temporal-ctbr",
                    worldActiveActionDimension: 4,
                    artifactPath: "seed-1/generation-2/vectorized-evaluation.json",
                    bestFitness: 0.57
                )
            ],
            acceptedCheckpoints: []
        )
        return model
    }

    private static func learningCampaignActivityEvents(
        now: Date
    ) throws -> [LearningCampaignProgressEvent] {
        var events: [LearningCampaignProgressEvent] = []
        for candidateIndex in 0..<60 {
            let generationIndex = candidateIndex / 24
            let generationCandidateIndex = candidateIndex % 24
            events.append(LearningCampaignProgressEvent(
                event: "candidate-evaluated",
                timestamp: now.addingTimeInterval(Double(candidateIndex * 3 - 240)),
                phase: "candidate",
                seed: "seed-1",
                generationIndex: generationIndex,
                candidateID: "g\(generationIndex)-c\(generationCandidateIndex)",
                fitness: 0.22 + Double(generationIndex) * 0.15
                    + Double(generationCandidateIndex) * 0.002,
                rewardAverage: -18 + Double(generationIndex) * 11
                    + Double(generationCandidateIndex) * 0.15,
                taskPassRate: min(1, 0.28 + Double(generationIndex) * 0.24),
                safetyViolationRate: max(0, 0.31 - Double(generationIndex) * 0.11),
                holdTimeRatio: min(1, 0.42 + Double(generationIndex) * 0.22),
                altitudeErrorRatio: max(0, 0.44 - Double(generationIndex) * 0.13),
                workerThroughput: 14.8,
                gpuAcceleration: true,
                tensorWorldBatch: true,
                tensorSummary: true,
                vectorizedPopulationSize: 24,
                vectorizedWorldCount: 24,
                vectorizedHistoryLength: 8,
                vectorizedObservationDimension: 32,
                vectorizedActionDimension: 4
            ))
            if generationCandidateIndex == 23 {
                events.append(LearningCampaignProgressEvent(
                    event: "generation-completed",
                    timestamp: now.addingTimeInterval(Double(candidateIndex * 3 - 239)),
                    status: "accepted",
                    phase: "generation",
                    seed: "seed-1",
                    generationIndex: generationIndex
                ))
            }
        }

        let scope = try TrainingWorkScope(
            runID: "preview-campaign",
            generationIndex: 2,
            candidateID: "g2-c12",
            batchID: "evaluation-g2",
            batchIndex: 12,
            batchCount: 24
        )
        let scenarioUnit = try TrainingWorkUnit(
            kind: .scenario,
            identifier: "6/KUY-ATT-1/1003",
            suiteIndex: 6,
            scenarioID: "KUY-ATT-1",
            scenarioSeed: 1_003
        )
        let controlStepUnit = try TrainingWorkUnit(
            kind: .controlStep,
            identifier: "6/KUY-ATT-1/1003/control-step",
            suiteIndex: 6,
            scenarioID: "KUY-ATT-1",
            scenarioSeed: 1_003
        )
        let workProgress = [
            try TrainingWorkProgress(
                scope: scope,
                phase: .candidateGate,
                state: .started,
                unit: scenarioUnit,
                completedUnitCount: 0,
                totalUnitCount: 6,
                populationSize: 24,
                timestamp: now.addingTimeInterval(-12)
            ),
            try TrainingWorkProgress(
                scope: scope,
                phase: .candidateGate,
                state: .advanced,
                unit: scenarioUnit,
                completedUnitCount: 2,
                totalUnitCount: 6,
                populationSize: 24,
                timestamp: now.addingTimeInterval(-1.2)
            ),
            try TrainingWorkProgress(
                scope: scope,
                phase: .candidateGate,
                state: .started,
                unit: controlStepUnit,
                completedUnitCount: 0,
                totalUnitCount: 240,
                populationSize: 24,
                timestamp: now.addingTimeInterval(-8)
            ),
            try TrainingWorkProgress(
                scope: scope,
                phase: .candidateGate,
                state: .advanced,
                unit: controlStepUnit,
                completedUnitCount: 148,
                totalUnitCount: 240,
                populationSize: 24,
                timestamp: now.addingTimeInterval(-0.5)
            )
        ]
        events.append(contentsOf: workProgress.map {
            LearningCampaignProgressEvent(
                event: .workProgress(seed: "seed-1", progress: $0),
                timestamp: $0.timestamp
            )
        })
        return events
    }

    private static func learningCampaignActivityPlan(
        artifactRoot: URL
    ) -> LearningCampaignPlan {
        LearningCampaignPlan(
            artifactRoot: artifactRoot.path,
            task: "attitude",
            searchSuites: ["6"],
            searchEpisodes: 6,
            acceptanceSuites: ["6", "7"],
            acceptanceEpisodes: 6,
            workers: 4,
            population: 24,
            generations: 6,
            eliteCount: 4,
            candidateEvaluationConcurrency: 24,
            cutPeriodSteps: 2,
            seeds: ["seed-1"],
            sourceCheckpoint: "/tmp/kuyu-preview/source.manasbundle",
            robotManifest: "/tmp/kuyu-preview/reference-quadrotor.kuyurobot.json",
            variation: "gaussian",
            searchStrategy: "qualityDiversity",
            mutationRate: 0.08,
            mutationNoiseScale: 0.01,
            bootstrapSuite: "6",
            bootstrapEpisodes: 1,
            bootstrapSequence: 8,
            bootstrapEpochs: 1,
            bootstrapMaxBatches: 1,
            bootstrapLearningRate: 0.001,
            bootstrapRepairAttempts: nil,
            verifyParentTask: true,
            resumeEnabled: true,
            resourceSampleSeconds: 1,
            artifactRetentionPolicy: .compact,
            availableDiskBytes: 1_000_000_000,
            requiredDiskBytes: 1_000_000,
            plannedCandidateEvaluations: 144,
            plannedRegressionRollouts: 288,
            plannedRegressionEpisodes: 1_728
        )
    }
}
