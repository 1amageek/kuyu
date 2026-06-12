import Foundation
@testable import KuyuMLX
import KuyuTraining
import Testing

@Test func manasMLXTrainingRunExecutorRejectsContinuationTaskMismatch() async throws {
    let sourceRoot = try makeContinuationArtifactRoot(
        task: "lift",
        trainingStageID: "evolution-search",
        trainingStageKind: .evolution
    )
    let destinationRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-task-destination-\(UUID().uuidString)", isDirectory: true)
    let request = TrainingResumeRequest(
        runID: "task-mismatch",
        source: .artifactRoot(sourceRoot),
        destinationArtifactRoot: destinationRoot,
        taskProfileID: "singleLift-v1",
        policyContract: singleLiftPolicyContract(),
        actionContract: singleLiftActionContract(),
        configuration: makeContinuationConfiguration(
            trainingStageID: "evolution-search",
            trainingStageKind: .evolution
        )
    )

    do {
        _ = try await ManasMLXTrainingRunExecutor().resume(request)
        Issue.record("Expected continuation task mismatch to reject before checkpoint selection.")
    } catch ManasMLXTrainingRunExecutorError.continuationTaskMismatch(let expected, let actual) {
        #expect(expected == "singleLift")
        #expect(actual == "lift")
    } catch {
        throw error
    }
}

private func singleLiftPolicyContract() -> LearningProjectPolicyContract {
    .simpleFeedForward(
        observationDimension: 8,
        actionDimension: 1,
        actionEncoding: .directMotor
    )
}

private func singleLiftActionContract() -> LearningProjectActionContract {
    LearningProjectActionContract(
        schemaID: "single-prop-drive-v1",
        kind: .continuous,
        driveCount: 1,
        actuatorCount: 1,
        isBounded: true,
        channels: [
            LearningProjectActionChannel(
                index: 0,
                name: "propellerThrust",
                unit: "normalized",
                normalizedLowerBound: 0,
                normalizedUpperBound: 1,
                outputTransform: .sigmoid
            )
        ]
    )
}

@Test func manasMLXTrainingRunExecutorRejectsContinuationStageKindMismatch() async throws {
    let sourceRoot = try makeContinuationArtifactRoot(
        task: "lift",
        trainingStageID: "closed-loop-reinforcement",
        trainingStageKind: .reinforcement
    )
    let destinationRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-kind-destination-\(UUID().uuidString)", isDirectory: true)
    let request = TrainingResumeRequest(
        runID: "stage-kind-mismatch",
        source: .artifactRoot(sourceRoot),
        destinationArtifactRoot: destinationRoot,
        taskProfileID: "lift-v1",
        policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
        actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
        configuration: makeContinuationConfiguration(
            trainingStageID: "evolution-search",
            trainingStageKind: .evolution
        )
    )

    do {
        _ = try await ManasMLXTrainingRunExecutor().resume(request)
        Issue.record("Expected continuation stage kind mismatch to reject before checkpoint selection.")
    } catch ManasMLXTrainingRunExecutorError.continuationStageKindMismatch(let expected, let actual) {
        #expect(expected == AutonomousTrainingStageKind.evolution.rawValue)
        #expect(actual == AutonomousTrainingStageKind.reinforcement.rawValue)
    } catch {
        throw error
    }
}

@Test func manasMLXTrainingRunExecutorRejectsContinuationStageIDMismatch() async throws {
    let sourceRoot = try makeContinuationArtifactRoot(
        task: "lift",
        trainingStageID: "alternate-evolution-stage",
        trainingStageKind: .evolution
    )
    let destinationRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-id-destination-\(UUID().uuidString)", isDirectory: true)
    let request = TrainingResumeRequest(
        runID: "stage-id-mismatch",
        source: .artifactRoot(sourceRoot),
        destinationArtifactRoot: destinationRoot,
        taskProfileID: "lift-v1",
        policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
        actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
        configuration: makeContinuationConfiguration(
            trainingStageID: "evolution-search",
            trainingStageKind: .evolution
        )
    )

    do {
        _ = try await ManasMLXTrainingRunExecutor().resume(request)
        Issue.record("Expected continuation stage ID mismatch to reject before checkpoint selection.")
    } catch ManasMLXTrainingRunExecutorError.continuationStageIDMismatch(let expected, let actual) {
        #expect(expected == "evolution-search")
        #expect(actual == "alternate-evolution-stage")
    } catch {
        throw error
    }
}

@Test func manasMLXTrainingRunExecutorUsesAcceptedRunCheckpointNotLooseFinalCheckpoint() throws {
    let acceptedCheckpoint = FileManager.default.temporaryDirectory
        .appendingPathComponent("accepted-\(UUID().uuidString).manasbundle", isDirectory: true)
    let looseCheckpoint = FileManager.default.temporaryDirectory
        .appendingPathComponent("loose-\(UUID().uuidString).manasbundle", isDirectory: true)
    let summary = makeExecutorCampaignSummary(
        finalCheckpoint: looseCheckpoint.path,
        acceptedCheckpoint: acceptedCheckpoint.path
    )

    do {
        _ = try LearningCampaignAcceptedCheckpointResolver().resolve(from: summary)
        Issue.record("Expected accepted checkpoint mismatch to reject the loose final checkpoint.")
    } catch LearningCampaignAcceptedCheckpointResolutionError.checkpointMismatch(let expected, let actual) {
        #expect(expected == acceptedCheckpoint.path)
        #expect(actual == looseCheckpoint.path)
    } catch {
        throw error
    }
}

@Test func manasMLXTrainingRunExecutorRejectsAcceptedSummaryWithoutCheckpointURL() throws {
    let finalCheckpoint = FileManager.default.temporaryDirectory
        .appendingPathComponent("accepted-\(UUID().uuidString).manasbundle", isDirectory: true)
    let summary = makeExecutorCampaignSummary(
        finalCheckpoint: finalCheckpoint.path,
        acceptedCheckpoint: nil
    )

    do {
        _ = try LearningCampaignAcceptedCheckpointResolver().resolve(from: summary)
        Issue.record("Expected missing accepted checkpoint URL to reject.")
    } catch LearningCampaignAcceptedCheckpointResolutionError.missingAcceptedCheckpoint {
    } catch {
        throw error
    }
}

@Test func manasMLXTrainingRunExecutorAcceptsFileURLAcceptedCheckpoint() throws {
    let acceptedCheckpoint = FileManager.default.temporaryDirectory
        .appendingPathComponent("accepted-\(UUID().uuidString).manasbundle", isDirectory: true)
    let summary = makeExecutorCampaignSummary(
        finalCheckpoint: acceptedCheckpoint.path,
        acceptedCheckpoint: acceptedCheckpoint.absoluteString
    )

    let optionalReference = try LearningCampaignAcceptedCheckpointResolver().resolve(from: summary)
    let reference = try #require(optionalReference)
    #expect(reference.url.path == acceptedCheckpoint.path)
    #expect(reference.kind == ModelBundleReferenceKind.accepted)
}

private func makeContinuationArtifactRoot(
    task: String,
    trainingStageID: String?,
    trainingStageKind: AutonomousTrainingStageKind?
) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-source-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let plan = makeContinuationPlan(
        root: root,
        task: task,
        trainingStageID: trainingStageID,
        trainingStageKind: trainingStageKind
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(plan)
    try data.write(to: root.appendingPathComponent("learning-campaign-plan.json"), options: .atomic)
    return root
}

private func makeContinuationConfiguration(
    trainingStageID: String?,
    trainingStageKind: AutonomousTrainingStageKind?
) -> TrainingRunConfiguration {
    TrainingRunConfiguration(
        trainingStageID: trainingStageID,
        trainingStageDisplayName: "Evolution Search",
        trainingStageKind: trainingStageKind,
        resources: TrainingResourcePlan(
            workerCount: 1,
            candidateEvaluationConcurrency: 1,
            resourceSampleSeconds: 0,
            worldExecutionRequirement: .acceleratorSharedWorld
        )
    )
}

private func makeExecutorCampaignSummary(
    finalCheckpoint: String,
    acceptedCheckpoint: String?
) -> LearningCampaignSummary {
    LearningCampaignSummary(
        artifactRoot: FileManager.default.temporaryDirectory
            .appendingPathComponent("executor-summary-\(UUID().uuidString)", isDirectory: true)
            .path,
        seedCount: 1,
        acceptedCount: 1,
        finalCheckpoint: finalCheckpoint,
        runs: [
            LearningCampaignSeedRunSummary(
                seed: "1",
                terminalState: "completed",
                accepted: true,
                acceptedCandidateID: "g0-c0",
                acceptedCheckpointURL: acceptedCheckpoint,
                incumbentCandidateID: nil,
                incumbentFitness: nil,
                bestCandidateID: "g0-c0",
                bestFitness: 1,
                bestVsIncumbentDelta: 1,
                bestTaskPassRate: 1,
                bestHoldTimeRatio: 1,
                bestAltitudeErrorRatio: 0,
                bestSafetyViolationRate: 0,
                bestRewardAverage: 1,
                gateNearestCandidateID: nil,
                gateNearestFitness: nil,
                gateNearestTaskPassRate: nil,
                gateNearestHoldTimeRatio: nil,
                gateNearestAltitudeErrorRatio: nil,
                gateNearestSafetyViolationRate: nil,
                gateNearestRewardAverage: nil,
                fitnessCount: 1,
                reasonCount: 0,
                evaluationTraceCount: 1,
                overlappedEvaluation: false
            )
        ]
    )
}

private func makeContinuationPlan(
    root: URL,
    task: String,
    trainingStageID: String?,
    trainingStageKind: AutonomousTrainingStageKind?
) -> LearningCampaignPlan {
    let pipeline = AutonomousTrainingPipelineFactory().defaultPlan(
        domain: .aerialDrone,
        taskProfileIDs: ["lift-v1"]
    )
    return LearningCampaignPlan(
        artifactRoot: root.path,
        task: task,
        trainingStageID: trainingStageID,
        trainingStageDisplayName: nil,
        trainingStageKind: trainingStageKind,
        suites: ["6"],
        episodes: 1,
        workers: 1,
        population: 100,
        generations: 1_000,
        eliteCount: 10,
        candidateEvaluationConcurrency: 100,
        seeds: ["1"],
        sourceCheckpoint: nil,
        robotManifest: nil,
        variation: "gaussian",
        searchStrategy: "qualityDiversity",
        mutationRate: 0.14,
        mutationNoiseScale: 0.025,
        bootstrapSuite: "6",
        bootstrapEpisodes: 0,
        bootstrapSequence: 0,
        bootstrapEpochs: 0,
        bootstrapMaxBatches: 0,
        bootstrapLearningRate: 0,
        bootstrapRepairAttempts: nil,
        verifyParentTask: true,
        resumeEnabled: false,
        resourceSampleSeconds: 0,
        artifactRetentionPolicy: .compact,
        availableDiskBytes: 1_000_000_000,
        requiredDiskBytes: 1,
        plannedCandidateEvaluations: 100_000,
        plannedRegressionRollouts: 100_000,
        plannedRegressionEpisodes: 100_000,
        autonomousPipeline: pipeline,
        convergence: LearningCampaignConvergencePlan(
            earlyStoppingEnabled: true,
            patienceGenerations: 50,
            minimumFitnessImprovement: 0.001,
            minimumTaskPassRateImprovement: 0.001,
            minimumHoldTimeRatioImprovement: 0.001
        )
    )
}
