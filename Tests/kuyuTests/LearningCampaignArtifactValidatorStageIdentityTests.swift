import Foundation
import KuyuMLX
import KuyuTraining
import Testing

@Test func learningCampaignArtifactValidatorRejectsMissingTrainingStageKind() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-campaign-missing-stage-kind-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writePlan(
        makePlan(
            root: root,
            trainingStageID: "evolution-search",
            trainingStageKind: nil
        ),
        to: root
    )

    let validation = try rejectedValidation(root: root)

    #expect(validation.issues.contains { $0.code == "missing-training-stage-kind" })
}

@Test func learningCampaignArtifactValidatorRejectsPipelineStageKindMismatch() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-campaign-stage-kind-mismatch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writePlan(
        makePlan(
            root: root,
            trainingStageID: "evolution-search",
            trainingStageKind: .reinforcement
        ),
        to: root
    )

    let validation = try rejectedValidation(root: root)

    #expect(validation.issues.contains { $0.code == "training-stage-kind-mismatch" })
}

private func rejectedValidation(root: URL) throws -> LearningCampaignValidation {
    let validation = try LearningCampaignArtifactValidationService().report(
        for: LearningCampaignArtifactValidationService.Request(
            artifactRoot: root,
            policy: .diagnosticFailedAndRunningCampaign,
            writesValidationArtifact: false
        )
    )
    #expect(!validation.valid)
    return validation
}

private func writePlan(_ plan: LearningCampaignPlan, to root: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(plan)
    try data.write(to: root.appendingPathComponent("learning-campaign-plan.json"), options: .atomic)
}

private func makePlan(
    root: URL,
    trainingStageID: String?,
    trainingStageKind: AutonomousTrainingStageKind?
) -> LearningCampaignPlan {
    let pipeline = AutonomousTrainingPipelineFactory().defaultPlan(
        domain: .aerialDrone,
        taskProfileIDs: ["lift-v1"]
    )
    return LearningCampaignPlan(
        artifactRoot: root.path,
        task: "lift",
        trainingStageID: trainingStageID,
        trainingStageDisplayName: nil,
        trainingStageKind: trainingStageKind,
        searchSuites: ["6"],
        searchEpisodes: 1,
        acceptanceSuites: ["6"],
        acceptanceEpisodes: 1,
        workers: 1,
        population: 100,
        generations: 1_000,
        eliteCount: 10,
        candidateEvaluationConcurrency: 100,
        cutPeriodSteps: 2,
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
