import Foundation
import KuyuMLX
import KuyuTraining
import Testing

@Test(.timeLimit(.minutes(1))) func continuationResolverRequiresPlan() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-missing-plan-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        removeContinuationTestDirectory(root)
    }

    do {
        _ = try LearningCampaignContinuationResolver().resolve(from: root)
        Issue.record("Expected continuation resolver to reject an artifact root without a plan.")
    } catch LearningCampaignContinuationError.missingPlan(let path) {
        #expect(path.hasSuffix("learning-campaign-plan.json"))
    } catch {
        throw error
    }
}

@Test(.timeLimit(.minutes(1))) func continuationResolverRejectsPlanFromDifferentArtifactRoot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-plan-root-\(UUID().uuidString)", isDirectory: true)
    let otherRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-plan-other-\(UUID().uuidString)", isDirectory: true)
    defer {
        removeContinuationTestDirectory(root)
        removeContinuationTestDirectory(otherRoot)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeContinuationJSON(
        makeContinuationResolverPlan(root: otherRoot, task: "lift"),
        to: root.appendingPathComponent("learning-campaign-plan.json")
    )

    do {
        _ = try LearningCampaignContinuationResolver().resolve(from: root)
        Issue.record("Expected continuation resolver to reject a plan from a different artifact root.")
    } catch LearningCampaignContinuationError.invalidPlan(let reason) {
        #expect(reason.contains("artifactRoot mismatch"))
    } catch {
        throw error
    }
}

@Test(.timeLimit(.minutes(1))) func continuationResolverIgnoresCandidateFitnessForOtherTask() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-task-filter-\(UUID().uuidString)", isDirectory: true)
    defer {
        removeContinuationTestDirectory(root)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeContinuationJSON(makeContinuationResolverPlan(root: root, task: "lift"), to: root.appendingPathComponent("learning-campaign-plan.json"))

    let evolution = root
        .appendingPathComponent("seeds", isDirectory: true)
        .appendingPathComponent("seed-1", isDirectory: true)
        .appendingPathComponent("evolution", isDirectory: true)
    let matchingCheckpoint = evolution
        .appendingPathComponent("candidates", isDirectory: true)
        .appendingPathComponent("generation-1", isDirectory: true)
        .appendingPathComponent("candidate-matching", isDirectory: true)
    let otherTaskCheckpoint = evolution
        .appendingPathComponent("candidates", isDirectory: true)
        .appendingPathComponent("generation-2", isDirectory: true)
        .appendingPathComponent("candidate-other-task", isDirectory: true)
    try writeContinuationCheckpointSkeleton(at: matchingCheckpoint)
    try writeContinuationCheckpointSkeleton(at: otherTaskCheckpoint)
    try FileManager.default.createDirectory(at: evolution, withIntermediateDirectories: true)
    try writeContinuationEvolutionManifest(at: evolution, task: "lift")

    try writeContinuationJSONLines([
        makeContinuationCandidate(id: "g1-c0", generation: 1, checkpoint: matchingCheckpoint),
        makeContinuationCandidate(id: "g2-c0", generation: 2, checkpoint: otherTaskCheckpoint)
    ], to: evolution.appendingPathComponent("candidates.jsonl"))
    try writeContinuationJSONLines([
        makeContinuationFitness(id: "g1-c0", generation: 1, task: "lift", fitness: 10),
        makeContinuationFitness(id: "g2-c0", generation: 2, task: "singleLift", fitness: 100)
    ], to: evolution.appendingPathComponent("fitness.jsonl"))

    let selection = try LearningCampaignContinuationResolver().resolve(from: root)

    #expect(selection.source == .bestCandidate)
    #expect(selection.candidateID == "g1-c0")
    #expect(selection.checkpointURL.standardizedFileURL == matchingCheckpoint.standardizedFileURL)
}

@Test(.timeLimit(.minutes(1))) func continuationResolverIgnoresExternalCandidateCheckpoint() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-root-filter-\(UUID().uuidString)", isDirectory: true)
    let externalRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-external-\(UUID().uuidString)", isDirectory: true)
    defer {
        removeContinuationTestDirectory(root)
        removeContinuationTestDirectory(externalRoot)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeContinuationJSON(makeContinuationResolverPlan(root: root, task: "lift"), to: root.appendingPathComponent("learning-campaign-plan.json"))

    let evolution = root
        .appendingPathComponent("seeds", isDirectory: true)
        .appendingPathComponent("seed-1", isDirectory: true)
        .appendingPathComponent("evolution", isDirectory: true)
    let internalCheckpoint = evolution
        .appendingPathComponent("candidates", isDirectory: true)
        .appendingPathComponent("generation-1", isDirectory: true)
        .appendingPathComponent("candidate-internal", isDirectory: true)
    let externalCheckpoint = externalRoot
        .appendingPathComponent("candidate-external.manasbundle", isDirectory: true)
    try writeContinuationCheckpointSkeleton(at: internalCheckpoint)
    try writeContinuationCheckpointSkeleton(at: externalCheckpoint)
    try FileManager.default.createDirectory(at: evolution, withIntermediateDirectories: true)
    try writeContinuationEvolutionManifest(at: evolution, task: "lift")

    try writeContinuationJSONLines([
        makeContinuationCandidate(id: "g1-c0", generation: 1, checkpoint: internalCheckpoint),
        makeContinuationCandidate(id: "g2-c0", generation: 2, checkpoint: externalCheckpoint)
    ], to: evolution.appendingPathComponent("candidates.jsonl"))
    try writeContinuationJSONLines([
        makeContinuationFitness(id: "g1-c0", generation: 1, task: "lift", fitness: 10),
        makeContinuationFitness(id: "g2-c0", generation: 2, task: "lift", fitness: 100)
    ], to: evolution.appendingPathComponent("fitness.jsonl"))

    let selection = try LearningCampaignContinuationResolver().resolve(from: root)

    #expect(selection.source == .bestCandidate)
    #expect(selection.candidateID == "g1-c0")
    #expect(selection.checkpointURL.standardizedFileURL == internalCheckpoint.standardizedFileURL)
}

@Test(.timeLimit(.minutes(1))) func continuationResolverAcceptsManifestCompleteCTBRCandidateWithoutReflexWeights() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-ctbr-\(UUID().uuidString)", isDirectory: true)
    defer {
        removeContinuationTestDirectory(root)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeContinuationJSON(makeContinuationResolverPlan(root: root, task: "lift"), to: root.appendingPathComponent("learning-campaign-plan.json"))

    let evolution = root
        .appendingPathComponent("seeds", isDirectory: true)
        .appendingPathComponent("seed-1", isDirectory: true)
        .appendingPathComponent("evolution", isDirectory: true)
    let ctbrCheckpoint = evolution
        .appendingPathComponent("candidates", isDirectory: true)
        .appendingPathComponent("generation-3", isDirectory: true)
        .appendingPathComponent("candidate-ctbr", isDirectory: true)
    try writeContinuationCTBRCheckpointSkeleton(at: ctbrCheckpoint)
    try FileManager.default.createDirectory(at: evolution, withIntermediateDirectories: true)
    try writeContinuationEvolutionManifest(at: evolution, task: "lift")

    try writeContinuationJSONLines([
        makeContinuationCandidate(id: "g3-c4", generation: 3, checkpoint: ctbrCheckpoint),
    ], to: evolution.appendingPathComponent("candidates.jsonl"))
    try writeContinuationJSONLines([
        makeContinuationFitness(id: "g3-c4", generation: 3, task: "lift", fitness: 123),
    ], to: evolution.appendingPathComponent("fitness.jsonl"))

    let selection = try LearningCampaignContinuationResolver().resolve(from: root)

    #expect(selection.source == .bestCandidate)
    #expect(selection.candidateID == "g3-c4")
    #expect(selection.checkpointURL.standardizedFileURL == ctbrCheckpoint.standardizedFileURL)
}

@Test(.timeLimit(.minutes(1))) func continuationResolverIgnoresCancelledEvolutionCandidates() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-cancelled-\(UUID().uuidString)", isDirectory: true)
    defer {
        removeContinuationTestDirectory(root)
    }
    let sourceCheckpoint = root
        .appendingPathComponent("training-continuation", isDirectory: true)
        .appendingPathComponent("SOURCE_SNAPSHOT", isDirectory: true)
    try writeContinuationCheckpointSkeleton(at: sourceCheckpoint)
    try writeContinuationJSON(
        makeContinuationResolverPlan(
            root: root,
            task: "lift",
            sourceCheckpoint: sourceCheckpoint.path,
            sourceCheckpointProvenance: "/tmp/ephemeral-launch-source"
        ),
        to: root.appendingPathComponent("learning-campaign-plan.json")
    )
    let evolution = root
        .appendingPathComponent("seeds", isDirectory: true)
        .appendingPathComponent("seed-1", isDirectory: true)
        .appendingPathComponent("evolution", isDirectory: true)
    let interruptedCheckpoint = evolution
        .appendingPathComponent("candidates", isDirectory: true)
        .appendingPathComponent("generation-0", isDirectory: true)
        .appendingPathComponent("candidate-interrupted", isDirectory: true)
    try writeContinuationCheckpointSkeleton(at: interruptedCheckpoint)
    try writeContinuationEvolutionManifest(
        at: evolution,
        task: "lift",
        terminalState: .cancelled
    )
    try writeContinuationJSONLines([
        makeContinuationCandidate(
            id: "g0-c0",
            generation: 0,
            checkpoint: interruptedCheckpoint
        ),
    ], to: evolution.appendingPathComponent("candidates.jsonl"))
    try writeContinuationJSONLines([
        makeContinuationFitness(
            id: "g0-c0",
            generation: 0,
            task: "lift",
            fitness: -1_000_000_000_000
        ),
    ], to: evolution.appendingPathComponent("fitness.jsonl"))
    try writeContinuationJSON(
        LearningCampaignSummary(
            artifactRoot: root.path,
            seedCount: 1,
            acceptedCount: 0,
            finalCheckpoint: sourceCheckpoint.path,
            runs: [
                LearningCampaignSeedRunSummary(
                    seed: "1",
                    terminalState: "cancelled",
                    accepted: false,
                    acceptedCandidateID: nil,
                    acceptedCheckpointURL: nil,
                    incumbentCandidateID: "g0-c0",
                    incumbentFitness: -1_000_000_000_000,
                    bestCandidateID: "g0-c0",
                    bestFitness: -1_000_000_000_000,
                    bestVsIncumbentDelta: 0,
                    bestTaskPassRate: 0,
                    bestHoldTimeRatio: 0,
                    bestAltitudeErrorRatio: 1,
                    bestSafetyViolationRate: 1,
                    bestRewardAverage: -1_000_000_000_000,
                    gateNearestCandidateID: "g0-c0",
                    gateNearestFitness: -1_000_000_000_000,
                    gateNearestTaskPassRate: 0,
                    gateNearestHoldTimeRatio: 0,
                    gateNearestAltitudeErrorRatio: 1,
                    gateNearestSafetyViolationRate: 1,
                    gateNearestRewardAverage: -1_000_000_000_000,
                    fitnessCount: 1,
                    reasonCount: 1,
                    evaluationTraceCount: 1,
                    overlappedEvaluation: false
                ),
            ]
        ),
        to: root.appendingPathComponent("learning-campaign-summary.json")
    )

    let selection = try LearningCampaignContinuationResolver().resolve(from: root)

    #expect(selection.source == .finalCheckpoint)
    #expect(selection.checkpointURL.standardizedFileURL == sourceCheckpoint.standardizedFileURL)
}

@Test(.timeLimit(.minutes(1))) func continuationResolverRejectsFinalCheckpointMismatchForAcceptedRun() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-final-mismatch-\(UUID().uuidString)", isDirectory: true)
    defer {
        removeContinuationTestDirectory(root)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeContinuationJSON(makeContinuationResolverPlan(root: root, task: "lift"), to: root.appendingPathComponent("learning-campaign-plan.json"))

    let acceptedCheckpoint = root.appendingPathComponent("accepted.manasbundle", isDirectory: true)
    let mismatchedCheckpoint = root.appendingPathComponent("mismatched.manasbundle", isDirectory: true)
    try writeContinuationCheckpointSkeleton(at: acceptedCheckpoint)
    try writeContinuationCheckpointSkeleton(at: mismatchedCheckpoint)
    try writeContinuationJSON(
        LearningCampaignSummary(
            artifactRoot: root.path,
            seedCount: 1,
            acceptedCount: 1,
            finalCheckpoint: mismatchedCheckpoint.path,
            runs: [
                makeContinuationSeedSummary(
                    accepted: true,
                    acceptedCheckpoint: acceptedCheckpoint
                )
            ]
        ),
        to: root.appendingPathComponent("learning-campaign-summary.json")
    )

    do {
        _ = try LearningCampaignContinuationResolver().resolve(from: root)
        Issue.record("Expected continuation resolver to reject a final checkpoint that does not match the accepted seed.")
    } catch LearningCampaignContinuationError.invalidSummary(let reason) {
        #expect(reason.contains("finalCheckpoint mismatch"))
    } catch {
        throw error
    }
}

@Test(.timeLimit(.minutes(1))) func continuationResolverRejectsSummaryFromDifferentArtifactRoot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-summary-root-\(UUID().uuidString)", isDirectory: true)
    let otherRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-summary-other-\(UUID().uuidString)", isDirectory: true)
    defer {
        removeContinuationTestDirectory(root)
        removeContinuationTestDirectory(otherRoot)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeContinuationJSON(
        makeContinuationResolverPlan(root: root, task: "lift"),
        to: root.appendingPathComponent("learning-campaign-plan.json")
    )
    let bootstrapCheckpoint = root.appendingPathComponent("bootstrap-checkpoint", isDirectory: true)
    try writeContinuationCheckpointSkeleton(at: bootstrapCheckpoint)
    try writeContinuationJSON(
        LearningCampaignSummary(
            artifactRoot: otherRoot.path,
            seedCount: 1,
            acceptedCount: 0,
            finalCheckpoint: bootstrapCheckpoint.path,
            runs: [
                makeContinuationSeedSummary(
                    accepted: false,
                    acceptedCheckpoint: nil
                )
            ]
        ),
        to: root.appendingPathComponent("learning-campaign-summary.json")
    )

    do {
        _ = try LearningCampaignContinuationResolver().resolve(from: root)
        Issue.record("Expected continuation resolver to reject a summary from a different artifact root.")
    } catch LearningCampaignContinuationError.invalidSummary(let reason) {
        #expect(reason.contains("artifactRoot mismatch"))
    } catch {
        throw error
    }
}

@Test(.timeLimit(.minutes(1))) func continuationResolverAcceptsSourceCheckpointFinalWhenNoSeedAccepted() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-source-final-\(UUID().uuidString)", isDirectory: true)
    let sourceCheckpoint = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-source-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("source.manasbundle", isDirectory: true)
    defer {
        removeContinuationTestDirectory(root)
        removeContinuationTestDirectory(sourceCheckpoint.deletingLastPathComponent())
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeContinuationCheckpointSkeleton(at: sourceCheckpoint)
    try writeContinuationJSON(
        makeContinuationResolverPlan(root: root, task: "lift", sourceCheckpoint: sourceCheckpoint.path),
        to: root.appendingPathComponent("learning-campaign-plan.json")
    )
    try writeContinuationJSON(
        LearningCampaignSummary(
            artifactRoot: root.path,
            seedCount: 1,
            acceptedCount: 0,
            finalCheckpoint: sourceCheckpoint.path,
            runs: [
                makeContinuationSeedSummary(
                    accepted: false,
                    acceptedCheckpoint: nil
                )
            ]
        ),
        to: root.appendingPathComponent("learning-campaign-summary.json")
    )

    let selection = try LearningCampaignContinuationResolver().resolve(from: root)

    #expect(selection.source == .finalCheckpoint)
    #expect(selection.checkpointURL.standardizedFileURL == sourceCheckpoint.standardizedFileURL)
}

@Test(.timeLimit(.minutes(1))) func continuationResolverRejectsExternalFinalCheckpointForAcceptedSeed() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-source-final-accepted-\(UUID().uuidString)", isDirectory: true)
    let sourceCheckpoint = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-source-accepted-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("source.manasbundle", isDirectory: true)
    defer {
        removeContinuationTestDirectory(root)
        removeContinuationTestDirectory(sourceCheckpoint.deletingLastPathComponent())
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeContinuationCheckpointSkeleton(at: sourceCheckpoint)
    try writeContinuationJSON(
        makeContinuationResolverPlan(root: root, task: "lift", sourceCheckpoint: sourceCheckpoint.path),
        to: root.appendingPathComponent("learning-campaign-plan.json")
    )
    try writeContinuationJSON(
        LearningCampaignSummary(
            artifactRoot: root.path,
            seedCount: 1,
            acceptedCount: 1,
            finalCheckpoint: sourceCheckpoint.path,
            runs: [
                makeContinuationSeedSummary(
                    accepted: true,
                    acceptedCheckpoint: sourceCheckpoint
                )
            ]
        ),
        to: root.appendingPathComponent("learning-campaign-summary.json")
    )

    do {
        _ = try LearningCampaignContinuationResolver().resolve(from: root)
        Issue.record("Expected continuation resolver to reject external accepted final checkpoints.")
    } catch LearningCampaignContinuationError.noCompleteCheckpoint(let path) {
        #expect(path == root.path)
    } catch {
        throw error
    }
}

@Test(.timeLimit(.minutes(1))) func continuationResolverRejectsExternalFinalCheckpointWhenNotPlanSource() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-final-not-source-\(UUID().uuidString)", isDirectory: true)
    let sourceCheckpoint = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-planned-source-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("source.manasbundle", isDirectory: true)
    let otherCheckpoint = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-continuation-other-source-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("other.manasbundle", isDirectory: true)
    defer {
        removeContinuationTestDirectory(root)
        removeContinuationTestDirectory(sourceCheckpoint.deletingLastPathComponent())
        removeContinuationTestDirectory(otherCheckpoint.deletingLastPathComponent())
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeContinuationCheckpointSkeleton(at: sourceCheckpoint)
    try writeContinuationCheckpointSkeleton(at: otherCheckpoint)
    try writeContinuationJSON(
        makeContinuationResolverPlan(root: root, task: "lift", sourceCheckpoint: sourceCheckpoint.path),
        to: root.appendingPathComponent("learning-campaign-plan.json")
    )
    try writeContinuationJSON(
        LearningCampaignSummary(
            artifactRoot: root.path,
            seedCount: 1,
            acceptedCount: 0,
            finalCheckpoint: otherCheckpoint.path,
            runs: [
                makeContinuationSeedSummary(
                    accepted: false,
                    acceptedCheckpoint: nil
                )
            ]
        ),
        to: root.appendingPathComponent("learning-campaign-summary.json")
    )

    do {
        _ = try LearningCampaignContinuationResolver().resolve(from: root)
        Issue.record("Expected continuation resolver to reject an external final checkpoint that is not the plan source.")
    } catch LearningCampaignContinuationError.invalidSummary(let reason) {
        #expect(reason.contains("finalCheckpoint mismatch"))
    } catch {
        throw error
    }
}

private func makeContinuationResolverPlan(
    root: URL,
    task: String,
    sourceCheckpoint: String? = nil,
    sourceCheckpointProvenance: String? = nil
) -> LearningCampaignPlan {
    LearningCampaignPlan(
        artifactRoot: root.path,
        task: task,
        trainingStageID: "evolution-search",
        trainingStageDisplayName: "Evolution Search",
        trainingStageKind: .evolution,
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
        sourceCheckpoint: sourceCheckpoint,
        sourceCheckpointProvenance: sourceCheckpointProvenance,
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
        autonomousPipeline: AutonomousTrainingPipelineFactory().defaultPlan(
            domain: .aerialDrone,
            taskProfileIDs: ["lift-v1"]
        ),
        convergence: LearningCampaignConvergencePlan(
            earlyStoppingEnabled: true,
            patienceGenerations: 50,
            minimumFitnessImprovement: 0.001,
            minimumTaskPassRateImprovement: 0.001,
            minimumHoldTimeRatioImprovement: 0.001
        )
    )
}

private func makeContinuationSeedSummary(
    accepted: Bool,
    acceptedCheckpoint: URL?
) -> LearningCampaignSeedRunSummary {
    LearningCampaignSeedRunSummary(
        seed: "1",
        terminalState: accepted ? "completed" : "rejected",
        accepted: accepted,
        acceptedCandidateID: accepted ? "g1-c0" : nil,
        acceptedCheckpointURL: acceptedCheckpoint?.path,
        incumbentCandidateID: nil,
        incumbentFitness: nil,
        bestCandidateID: nil,
        bestFitness: nil,
        bestVsIncumbentDelta: nil,
        bestTaskPassRate: nil,
        bestHoldTimeRatio: nil,
        bestAltitudeErrorRatio: nil,
        bestSafetyViolationRate: nil,
        bestRewardAverage: nil,
        gateNearestCandidateID: nil,
        gateNearestFitness: nil,
        gateNearestTaskPassRate: nil,
        gateNearestHoldTimeRatio: nil,
        gateNearestAltitudeErrorRatio: nil,
        gateNearestSafetyViolationRate: nil,
        gateNearestRewardAverage: nil,
        fitnessCount: 0,
        reasonCount: accepted ? 0 : 1,
        evaluationTraceCount: 0,
        overlappedEvaluation: false
    )
}

private func makeContinuationCandidate(id: String, generation: Int, checkpoint: URL) -> GenomeCandidate {
    GenomeCandidate(
        runID: "continuation-test",
        generationIndex: generation,
        candidateID: id,
        genomeID: "continuation-test-\(id)",
        checkpointID: id,
        checkpointURL: checkpoint,
        mutationRate: 0.08,
        mutationNoiseScale: 0.01,
        mutationSummary: "test-candidate"
    )
}

private func makeContinuationFitness(id: String, generation: Int, task: String, fitness: Double) -> FitnessSummary {
    FitnessSummary(
        runID: "continuation-test",
        generationIndex: generation,
        candidateID: id,
        taskID: task,
        scalarFitness: fitness,
        rewardAverage: fitness,
        taskPassRate: 0,
        safetyViolationRate: 0,
        holdTimeRatio: 0,
        altitudeErrorRatio: 1
    )
}

private func writeContinuationEvolutionManifest(
    at evolution: URL,
    task: String,
    terminalState: EvolutionRunTerminalState = .completed
) throws {
    try FileManager.default.createDirectory(at: evolution, withIntermediateDirectories: true)
    let completedAt: Date? = terminalState == .running ? nil : Date(timeIntervalSince1970: 1)
    try writeContinuationJSON(
        EvolutionRunManifest(
            runID: "continuation-test",
            taskID: task,
            configHash: "continuation-config",
            policyID: "continuation-policy",
            populationSize: 2,
            generationCount: 4,
            eliteCount: 1,
            workerCount: 1,
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: completedAt,
            terminalState: terminalState
        ),
        to: evolution.appendingPathComponent("evolution-manifest.json")
    )
}

private func writeContinuationCheckpointSkeleton(at url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: url.appendingPathComponent("model.json"), options: [.atomic])
    try Data("core".utf8).write(to: url.appendingPathComponent("core.safetensors"), options: [.atomic])
    try Data("reflex".utf8).write(to: url.appendingPathComponent("reflex.safetensors"), options: [.atomic])
    try Data(ContinuationBundleManifestFixture.json.utf8).write(
        to: url.appendingPathComponent("manas-bundle.json"),
        options: [.atomic]
    )
}

private func writeContinuationCTBRCheckpointSkeleton(at url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: url.appendingPathComponent("model.json"), options: [.atomic])
    try Data("core".utf8).write(to: url.appendingPathComponent("core.safetensors"), options: [.atomic])
    try Data(ContinuationCTBRBundleManifestFixture.json.utf8).write(
        to: url.appendingPathComponent("manas-bundle.json"),
        options: [.atomic]
    )
}

private enum ContinuationBundleManifestFixture {
    static let json = """
    {
      "bundleID" : "fixture",
      "components" : [
        {
          "contentType" : "application/json",
          "path" : "model.json",
          "required" : true,
          "role" : "modelConfig"
        },
        {
          "contentType" : "application/vnd.safetensors",
          "path" : "core.safetensors",
          "required" : true,
          "role" : "coreWeights"
        },
        {
          "contentType" : "application/vnd.safetensors",
          "path" : "reflex.safetensors",
          "required" : true,
          "role" : "reflexWeights"
        }
      ],
      "createdAt" : "1970-01-01T00:00:00Z",
      "modelFamily" : "manas",
      "runtimeContract" : {
        "configHash" : "config",
        "embodimentHash" : "embodiment",
        "driveSemanticsID" : "drive",
        "observationSchemaID" : "observation"
      },
      "schemaVersion" : 1
    }
    """
}

private enum ContinuationCTBRBundleManifestFixture {
    static let json = """
    {
      "bundleID" : "ctbr-fixture",
      "components" : [
        {
          "contentType" : "application/json",
          "path" : "model.json",
          "required" : true,
          "role" : "modelConfig"
        },
        {
          "contentType" : "application/vnd.safetensors",
          "path" : "core.safetensors",
          "required" : true,
          "role" : "coreWeights"
        }
      ],
      "createdAt" : "1970-01-01T00:00:00Z",
      "modelFamily" : "manas-temporal-ctbr",
      "runtimeContract" : {
        "configHash" : "config",
        "embodimentHash" : "embodiment",
        "driveSemanticsID" : "ctbr",
        "observationSchemaID" : "temporal-ctbr"
      },
      "schemaVersion" : 1
    }
    """
}

private func writeContinuationJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try data.write(to: url, options: .atomic)
}

private func writeContinuationJSONLines<T: Encodable>(_ values: [T], to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let lines = try values.map { value in
        let data = try encoder.encode(value)
        guard let line = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(value, EncodingError.Context(
                codingPath: [],
                debugDescription: "JSON line could not be represented as UTF-8."
            ))
        }
        return line
    }
    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
}

private func removeContinuationTestDirectory(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return
    }
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Temporary directory cleanup failed: \(error)")
    }
}
