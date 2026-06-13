import Foundation
import KuyuTraining
@testable import KuyuUI
import Testing

@MainActor
@Test(.timeLimit(.minutes(1))) func simulationViewModelLiveMetricsKeepGenerationBestSeries() {
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))

    model.appendLearningCampaignLiveMetricSamples(makeFitness(
        generationIndex: 0,
        candidateID: "g0-c0",
        scalarFitness: -10,
        rewardAverage: -20,
        taskPassRate: 0.25
    ))
    model.appendLearningCampaignLiveMetricSamples(makeFitness(
        generationIndex: 0,
        candidateID: "g0-c1",
        scalarFitness: -12,
        rewardAverage: -30,
        taskPassRate: 0.1
    ))
    model.appendLearningCampaignLiveMetricSamples(makeFitness(
        generationIndex: 0,
        candidateID: "g0-c2",
        scalarFitness: -8,
        rewardAverage: -18,
        taskPassRate: 0.5
    ))
    model.appendLearningCampaignLiveMetricSamples(makeFitness(
        generationIndex: 1,
        candidateID: "g1-c0",
        scalarFitness: -7,
        rewardAverage: -16,
        taskPassRate: 0.75
    ))

    #expect(model.learningCampaignLiveCandidateEvaluationCount == 4)
    #expect(model.learningCampaignLiveFitnessSamples.map { $0.time } == [0, 1])
    #expect(model.learningCampaignLiveFitnessSamples.map { $0.value } == [-8, -7])
    #expect(model.learningCampaignLiveRewardSamples.map { $0.value } == [-18, -16])
    #expect(model.learningCampaignLiveTaskPassSamples.map { $0.value } == [0.5, 0.75])
}

@MainActor
@Test(.timeLimit(.minutes(1))) func simulationViewModelExposesLiveVectorizedProgressForDashboardViews() {
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.appendLearningCampaignLiveProgressRecord(
        LearningCampaignProgressRecord(
            event: "candidate-evaluated",
            timestamp: "2026-05-16T00:00:00Z",
            status: nil,
            exitCode: nil,
            phase: "candidate",
            seed: "seed-1",
            generationIndex: 3,
            candidateID: "g3-c42",
            fitness: -12.5,
            rewardAverage: -4.2,
            taskPassRate: 0.25,
            safetyViolationRate: 0,
            holdTimeRatio: 0.1,
            altitudeErrorRatio: 0.2,
            workerThroughput: 18.5,
            gpuAcceleration: true,
            tensorWorldBatch: true,
            tensorSummary: true,
            vectorizedPopulationSize: 100,
            vectorizedWorldCount: 100,
            vectorizedHistoryLength: 32,
            vectorizedObservationDimension: 64,
            vectorizedActionDimension: 4,
            failureReasons: [],
            message: "Candidate evaluated"
        )
    )

    let records = model.learningCampaignProgressEventsForDisplay

    #expect(records.count == 1)
    #expect(records.first?.candidateID == "g3-c42")
    #expect(records.first?.gpuAcceleration == true)
    #expect(records.first?.tensorWorldBatch == true)
    #expect(records.first?.vectorizedPopulationSize == 100)
    #expect(records.first?.vectorizedWorldCount == 100)
}

@Test(.timeLimit(.minutes(1))) func gpuActivitySnapshotSummarizesLiveAndBatchExecution() {
    let records = [
        LearningCampaignProgressRecord(
            event: "candidate-evaluated",
            timestamp: "2026-05-16T00:00:00Z",
            status: nil,
            exitCode: nil,
            phase: "candidate",
            seed: "seed-1",
            generationIndex: 4,
            candidateID: "g4-c0",
            workerThroughput: 12,
            gpuAcceleration: true,
            tensorWorldBatch: true,
            tensorSummary: true
        ),
        LearningCampaignProgressRecord(
            event: "candidate-evaluated",
            timestamp: "2026-05-16T00:00:01Z",
            status: nil,
            exitCode: nil,
            phase: "candidate",
            seed: "seed-1",
            generationIndex: 4,
            candidateID: "g4-c1",
            workerThroughput: 8,
            gpuAcceleration: false,
            tensorWorldBatch: false,
            tensorSummary: false
        )
    ]
    let batches = [
        LearningCampaignVectorizedBatchState(
            kind: .evaluation,
            seed: "seed-1",
            generationIndex: 4,
            candidateCount: 96,
            completedCandidateCount: 48,
            elapsedSeconds: 6,
            acceleratorDevice: "Apple M4 Max",
            policyExecutionMode: "mlx-temporal-ctbr-policy-v1",
            observationExecutionMode: "mlx-tensor-ctbr-observation-history-v1",
            worldExecutionMode: "mlx-tensor-shared-world-v1",
            actionEncoding: "ctbr",
            worldActiveActionDimension: 4,
            artifactPath: "/tmp/vectorized-evaluations/g4.json",
            bestFitness: -1
        )
    ]

    let snapshot = LearningCampaignGPUActivitySnapshot(
        batches: batches,
        progressEvents: records,
        acceleratorLabel: "Apple M4 Max",
        currentAllocatedBytes: 256,
        recommendedMaxWorkingSetBytes: 1_024
    )

    #expect(snapshot.statusLabel == "ready")
    #expect(snapshot.latestExecutionLabel == "CPU")
    #expect(snapshot.latestThroughput == 8)
    #expect(snapshot.peakThroughput == 12)
    #expect(snapshot.gpuBackedEventCount == 1)
    #expect(snapshot.knownEventCount == 2)
    #expect(snapshot.gpuBackedEventFraction == 0.5)
    #expect(snapshot.gpuBackedBatchCount == 1)
    #expect(snapshot.totalBatchCount == 1)
    #expect(snapshot.gpuBackedBatchFraction == 1)
    #expect(snapshot.latestBatchFillFraction == 0.5)
    #expect(snapshot.metalMemoryFraction == 0.25)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func simulationViewModelBuildsChartSamplesFromProgressEvents() {
    let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))

    model.appendLearningCampaignLiveProgressEvent(makeProgressEvent(
        generationIndex: 2,
        candidateID: "g2-c0",
        fitness: -12,
        rewardAverage: -30,
        taskPassRate: 0.1
    ))
    model.appendLearningCampaignLiveProgressEvent(makeProgressEvent(
        generationIndex: 2,
        candidateID: "g2-c1",
        fitness: -8,
        rewardAverage: -18,
        taskPassRate: 0.5
    ))
    model.appendLearningCampaignLiveProgressEvent(makeProgressEvent(
        generationIndex: 3,
        candidateID: "g3-c0",
        fitness: -6,
        rewardAverage: -14,
        taskPassRate: 0.75
    ))

    #expect(model.learningCampaignLiveCandidateEvaluationCount == 3)
    #expect(model.learningCampaignLiveFitnessSamples.map(\.time) == [2, 3])
    #expect(model.learningCampaignLiveFitnessSamples.map(\.value) == [-8, -6])
    #expect(model.learningCampaignLiveRewardSamples.map(\.value) == [-18, -14])
    #expect(model.learningCampaignLiveTaskPassSamples.map(\.value) == [0.5, 0.75])
    #expect(model.learningCampaignLiveProgressEvents.last?.gpuAcceleration == true)
    #expect(model.learningCampaignLiveProgressEvents.last?.tensorWorldBatch == true)
    #expect(model.learningCampaignLiveProgressEvents.last?.vectorizedPopulationSize == 100)
}

private func makeFitness(
    generationIndex: Int,
    candidateID: String,
    scalarFitness: Double,
    rewardAverage: Double,
    taskPassRate: Double
) -> FitnessSummary {
    FitnessSummary(
        runID: "run",
        generationIndex: generationIndex,
        candidateID: candidateID,
        taskID: "lift",
        scalarFitness: scalarFitness,
        rewardAverage: rewardAverage,
        taskPassRate: taskPassRate,
        safetyViolationRate: 0,
        holdTimeRatio: taskPassRate,
        altitudeErrorRatio: 1 - taskPassRate
    )
}

private func makeProgressEvent(
    generationIndex: Int,
    candidateID: String,
    fitness: Double,
    rewardAverage: Double,
    taskPassRate: Double
) -> TrainingRunProgressEvent {
    TrainingRunProgressEvent(
        timestamp: Date(timeIntervalSince1970: Double(generationIndex)),
        event: "candidate-evaluated",
        phase: "candidate",
        seed: "seed-1",
        generationIndex: generationIndex,
        candidateID: candidateID,
        fitness: fitness,
        rewardAverage: rewardAverage,
        taskPassRate: taskPassRate,
        safetyViolationRate: 0,
        holdTimeRatio: taskPassRate,
        altitudeErrorRatio: 1 - taskPassRate,
        workerThroughput: 10,
        gpuAcceleration: true,
        tensorWorldBatch: true,
        tensorSummary: true,
        vectorizedPopulationSize: 100,
        vectorizedWorldCount: 100,
        vectorizedHistoryLength: 32,
        vectorizedObservationDimension: 64,
        vectorizedActionDimension: 4,
        failureReasons: []
    )
}
