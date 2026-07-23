import Foundation
import KuyuMLX
import KuyuMLXCampaignContracts
import KuyuTraining
import KuyuUI
import Testing

@Test func learningCampaignRunStoreLoadsCampaignArtifacts() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-campaign-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    try writeJSON(makePlan(root: root), to: root.appendingPathComponent("learning-campaign-plan.json"))
    try writeJSON(
        LearningCampaignStatus(
            status: "running",
            exitCode: 0,
            startedAt: "2026-05-07T00:00:00Z",
            finishedAt: ""
        ),
        to: root.appendingPathComponent("campaign-status.json")
    )
    try writeValidationReceipt(root: root)
    try writeLine(
        LearningCampaignProgressEvent(
            event: "seed-started",
            timestamp: Date(timeIntervalSince1970: 1_778_112_002),
            status: "running",
            exitCode: nil
        ),
        to: root.appendingPathComponent("progress.jsonl")
    )

    let evolutionRoot = root
        .appendingPathComponent("seeds", isDirectory: true)
        .appendingPathComponent("seed-1", isDirectory: true)
        .appendingPathComponent("evolution", isDirectory: true)
    try FileManager.default.createDirectory(at: evolutionRoot, withIntermediateDirectories: true)
    try writeLine(
        PopulationGenerationRecord(
            runID: "run-1",
            generationIndex: 1,
            candidateCount: 4,
            evaluatedCandidateCount: 4,
            eliteCandidateIDs: ["candidate-0"],
            bestCandidateID: "candidate-0",
            bestFitness: 42,
            incumbentCandidateID: "incumbent",
            incumbentFitness: 40,
            bestVsIncumbentDelta: 2,
            minimumImprovementOverIncumbent: 0.05,
            incumbentImproved: true,
            mutationRate: 0.02,
            mutationNoiseScale: 0.01,
            accepted: false,
            rejectionReasons: ["minimum-incumbent-improvement"],
            createdAt: Date(timeIntervalSince1970: 1_778_112_000)
        ),
        to: evolutionRoot.appendingPathComponent("generations.jsonl")
    )

    let state = try LearningCampaignRunStore().load(from: root)

    #expect(state.task == "singleLift")
    #expect(state.statusLabel == "running")
    #expect(state.validationLabel == "recorded strict valid")
    #expect(state.progressEvents.count == 1)
    #expect(state.generations.count == 1)
    #expect(state.bestDelta == 2)
    #expect(state.latestGenerations.first?.incumbentImproved == true)
}

@Test func learningCampaignRunStoreSurfacesValidationReceiptCorruption() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-corrupt-receipt-\(UUID().uuidString)", isDirectory: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove validation receipt fixture: \(error)")
        }
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeValidationReceipt(root: root)

    let aliasURL = root.appendingPathComponent(
        LearningCampaignValidationReceiptStore.strictAliasFileName
    )
    let locator = try JSONDecoder().decode(
        LearningCampaignValidationReceiptLocator.self,
        from: Data(contentsOf: aliasURL)
    )
    let objectURL = root
        .appendingPathComponent(
            LearningCampaignValidationReceiptStore.receiptDirectoryName,
            isDirectory: true
        )
        .appendingPathComponent("\(locator.contentSHA256).json")
    try Data("tampered".utf8).write(to: objectURL, options: [.atomic])

    let state = try LearningCampaignRunStore().load(from: root)

    #expect(state.validation == nil)
    #expect(state.validationLabel == "recorded strict receipt invalid")
    #expect(state.validationReceiptIssue != nil)
    #expect(state.diagnosticText.contains("validationReceiptIssue="))
}

@Test func learningCampaignRunStoreKeepsStrictValidationWhenDiagnosticReceiptIsCorrupt() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-corrupt-diagnostic-receipt-\(UUID().uuidString)", isDirectory: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove validation receipt fixture: \(error)")
        }
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeValidationReceipt(root: root)
    try writeValidationReceipt(root: root, policy: .diagnosticFailedAndRunningCampaign)

    let aliasURL = root.appendingPathComponent(
        LearningCampaignValidationReceiptStore.diagnosticAliasFileName
    )
    let locator = try JSONDecoder().decode(
        LearningCampaignValidationReceiptLocator.self,
        from: Data(contentsOf: aliasURL)
    )
    let objectURL = root
        .appendingPathComponent(
            LearningCampaignValidationReceiptStore.receiptDirectoryName,
            isDirectory: true
        )
        .appendingPathComponent("\(locator.contentSHA256).json")
    try Data("tampered".utf8).write(to: objectURL, options: [.atomic])

    let state = try LearningCampaignRunStore().load(from: root)

    #expect(state.strictValidation?.valid == true)
    #expect(state.diagnosticValidation == nil)
    #expect(state.diagnosticValidationReceiptIssue != nil)
    #expect(state.validationLabel == "recorded strict valid")
    #expect(state.diagnosticText.contains("diagnosticValidationReceiptIssue="))
}

@Test func learningCampaignRunStoreLoadsFiveGenerationHistory() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-campaign-five-gen-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    try writeJSON(makeFiveGenerationPlan(root: root), to: root.appendingPathComponent("learning-campaign-plan.json"))
    try writeJSON(
        LearningCampaignStatus(
            status: "succeeded",
            exitCode: 0,
            startedAt: "2026-05-07T00:00:00Z",
            finishedAt: "2026-05-07T00:05:00Z"
        ),
        to: root.appendingPathComponent("campaign-status.json")
    )

    let evolutionRoot = root
        .appendingPathComponent("seeds", isDirectory: true)
        .appendingPathComponent("seed-1", isDirectory: true)
        .appendingPathComponent("evolution", isDirectory: true)
    try FileManager.default.createDirectory(at: evolutionRoot, withIntermediateDirectories: true)
    for generation in 0..<5 {
        try writeLine(
            PopulationGenerationRecord(
                runID: "run-1",
                generationIndex: generation,
                candidateCount: 8,
                evaluatedCandidateCount: 8,
                eliteCandidateIDs: ["g\(generation)-c0", "g\(generation)-c1"],
                bestCandidateID: "g\(generation)-c0",
                bestFitness: Double(generation + 1) * 10,
                incumbentCandidateID: generation == 0 ? "parent" : "g\(generation - 1)-c0",
                incumbentFitness: Double(generation) * 10,
                bestVsIncumbentDelta: 10,
                minimumImprovementOverIncumbent: 0,
                incumbentImproved: true,
                mutationRate: 0.08,
                mutationNoiseScale: 0.01,
                accepted: generation == 4,
                rejectionReasons: generation == 4 ? [] : ["continuing-search"],
                createdAt: Date(timeIntervalSince1970: 1_778_112_000 + Double(generation))
            ),
            to: evolutionRoot.appendingPathComponent("generations.jsonl")
        )
    }

    let state = try LearningCampaignRunStore().load(from: root)

    #expect(state.plan?.generations == 5)
    #expect(state.plan?.population == 8)
    #expect(state.plan?.candidateEvaluationConcurrency == 8)
    #expect(state.generations.count == 5)
    #expect(state.latestGenerations.first?.generationIndex == 4)
    #expect(state.latestGenerations.first?.bestFitness == 50)
}

@Test func learningCampaignRunStoreDerivesLiveProgressFromProgressEvents() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-campaign-live-progress-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    try writeJSON(makeFiveGenerationPlan(root: root), to: root.appendingPathComponent("learning-campaign-plan.json"))
    try writeLine(
        LearningCampaignProgressEvent(
            event: "candidate-evaluated",
            timestamp: Date(timeIntervalSince1970: 1_778_112_002),
            status: nil,
            exitCode: nil,
            phase: "candidate",
            seed: "1",
            generationIndex: 0,
            candidateID: "g0-c0",
            fitness: -10,
            rewardAverage: -10,
            taskPassRate: 0,
            safetyViolationRate: 1,
            holdTimeRatio: 0.2,
            altitudeErrorRatio: 0.8,
            workerThroughput: 2,
            failureReasons: ["lift-unsettled"]
        ),
        to: root.appendingPathComponent("progress.jsonl")
    )
    try writeLine(
        LearningCampaignProgressEvent(
            event: "generation-completed",
            timestamp: Date(timeIntervalSince1970: 1_778_112_003),
            status: nil,
            exitCode: nil,
            phase: "generation",
            seed: "1",
            generationIndex: 0,
            bestCandidateID: "g0-c0"
        ),
        to: root.appendingPathComponent("progress.jsonl")
    )
    try writeLine(
        LearningCampaignProgressEvent(
            event: "candidate-evaluated",
            timestamp: Date(timeIntervalSince1970: 1_778_112_004),
            status: nil,
            exitCode: nil,
            phase: "candidate",
            seed: "1",
            generationIndex: 1,
            candidateID: "g1-c0",
            fitness: -8,
            rewardAverage: -8,
            taskPassRate: 0.25,
            safetyViolationRate: 0.5,
            holdTimeRatio: 0.4,
            altitudeErrorRatio: 0.6,
            workerThroughput: 3
        ),
        to: root.appendingPathComponent("progress.jsonl")
    )

    let state = try LearningCampaignRunStore().load(from: root)

    #expect(state.completedGenerationCount == 1)
    #expect(state.plannedGenerationCount == 5)
    #expect(state.liveCandidateEvaluationCount == 2)
    #expect(state.plannedCandidateEvaluationCount == 40)
    #expect(state.campaignProgressFraction == 0.05)
    #expect(state.bestFitness == -8)
    #expect(state.bestFitnessDeltaFromInitial == 2)
    #expect(state.bestTaskPassRate == 0.25)
    #expect(state.bestHoldTimeRatio == 0.4)
    #expect(state.bestAltitudeErrorRatio == 0.6)
    #expect(state.liveBestFitnessSamples.map(\.value) == [-10, -8])
    #expect(state.liveRewardAverageSamples.map(\.value) == [-10, -8])
    #expect(state.liveTaskPassRateSamples.map(\.value) == [0, 0.25])
    #expect(state.liveHoldTimeRatioSamples.map(\.value) == [0.2, 0.4])
    #expect(state.liveAltitudeErrorRatioSamples.map(\.value) == [0.8, 0.6])
}

@Test func learningCampaignRunStoreUsesCommittedReinforcementIterationProgress() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-rr-ppo-progress-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeJSON(makeFiveGenerationPlan(root: root), to: root.appendingPathComponent("learning-campaign-plan.json"))

    let baseline = try LearningCampaignReinforcementHealthSummary(
        episodeCount: 4,
        failureCount: 2,
        rewardAverage: -2,
        maximumAngularRate: 2,
        maximumAttitudeDeviation: 0.8,
        minimumRootAltitude: 0.4
    )
    let retained = try LearningCampaignReinforcementHealthSummary(
        episodeCount: 4,
        failureCount: 1,
        rewardAverage: -1,
        maximumAngularRate: 1,
        maximumAttitudeDeviation: 0.4,
        minimumRootAltitude: 0.8
    )
    let progress = try LearningCampaignReinforcementIterationProgress(
        runID: "rr-ppo-run",
        globalIteration: 2,
        completedIterationCount: 3,
        totalIterationCount: 10,
        selectedCandidateID: "candidate-2",
        accepted: true,
        materiallyImproved: true,
        currentHorizonSteps: 512,
        fullHorizonSteps: 10_000,
        actorLearningRate: 0.00002,
        scopeProgress: [
            try LearningCampaignReinforcementScopeProgress(
                scopeID: "frontier-512",
                role: .frontier,
                horizonSteps: 512,
                baseline: baseline,
                retained: retained
            ),
        ],
        observedCost: 0.02,
        costLimit: 0.04,
        dualLambda: 0.1,
        constraintEpisodeCount: 4,
        constraintTransitionCount: 2_048,
        artifactPath: "/tmp/rr-ppo-iteration.json",
        artifactSHA256: String(repeating: "a", count: 64),
        timestamp: Date(timeIntervalSince1970: 1_778_112_005)
    )
    let workProgress = try TrainingWorkProgress(
        scope: TrainingWorkScope(runID: "rr-ppo-run", iterationIndex: 2),
        phase: .optimization,
        state: .advanced,
        unit: TrainingWorkUnit(kind: .epoch, identifier: "rr-ppo-iterations"),
        completedUnitCount: 3,
        totalUnitCount: 10,
        timestamp: progress.timestamp
    )
    try writeLine(
        LearningCampaignProgressEvent(
            event: .workProgress(seed: nil, progress: workProgress),
            timestamp: progress.timestamp
        ),
        to: root.appendingPathComponent("progress.jsonl")
    )
    try writeLine(
        LearningCampaignProgressEvent(
            event: .reinforcementIterationCompleted(seed: nil, progress: progress),
            timestamp: progress.timestamp
        ),
        to: root.appendingPathComponent("progress.jsonl")
    )

    let state = try LearningCampaignRunStore().load(from: root)

    #expect(state.latestReinforcementIteration == progress)
    #expect(state.latestReinforcementIteration?.fractionCompleted == 0.3)
    #expect(state.activeReinforcementIteration == progress)
    #expect(state.campaignProgressFraction == 0)
    #expect(state.progress.lifecycleStage == .reinforcing)

    try writeLine(
        LearningCampaignProgressEvent(
            event: .parentEvaluationStarted(
                label: "initial-parent",
                checkpointPath: "/tmp/checkpoint"
            ),
            timestamp: Date(timeIntervalSince1970: 1_778_112_006)
        ),
        to: root.appendingPathComponent("progress.jsonl")
    )
    let evaluatingState = try LearningCampaignRunStore().load(from: root)
    #expect(evaluatingState.latestReinforcementIteration == progress)
    #expect(evaluatingState.activeReinforcementIteration == nil)
    #expect(evaluatingState.progress.lifecycleStage == .evaluatingParent)
}

@Test func learningCampaignRunStoreAggregatesFailureDiagnostics() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-campaign-failure-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    try writeJSON(makePlan(root: root), to: root.appendingPathComponent("learning-campaign-plan.json"))
    try writeJSON(
        LearningCampaignStatus(
            status: "failed",
            exitCode: 1,
            startedAt: "2026-05-07T00:00:00Z",
            finishedAt: "2026-05-07T00:01:00Z"
        ),
        to: root.appendingPathComponent("campaign-status.json")
    )
    try writeValidationReceipt(
        root: root,
        valid: false,
        issues: [
            LearningCampaignValidationIssue(
                code: "accepted-checkpoint-missing",
                detail: "accepted checkpoint artifact is missing"
            )
        ]
    )
    try writeLine(
        LearningCampaignProgressEvent(
            event: "validation-failed",
            timestamp: Date(timeIntervalSince1970: 1_778_112_062),
            status: "failed",
            exitCode: 1
        ),
        to: root.appendingPathComponent("progress.jsonl")
    )

    let evolutionRoot = root
        .appendingPathComponent("seeds", isDirectory: true)
        .appendingPathComponent("seed-1", isDirectory: true)
        .appendingPathComponent("evolution", isDirectory: true)
    try FileManager.default.createDirectory(at: evolutionRoot, withIntermediateDirectories: true)
    try writeLine(
        PopulationGenerationRecord(
            runID: "run-1",
            generationIndex: 0,
            candidateCount: 4,
            evaluatedCandidateCount: 4,
            eliteCandidateIDs: ["candidate-0"],
            bestCandidateID: "candidate-0",
            bestFitness: 10,
            incumbentCandidateID: "parent",
            incumbentFitness: 10,
            bestVsIncumbentDelta: 0,
            minimumImprovementOverIncumbent: 0.01,
            incumbentImproved: false,
            mutationRate: 0.08,
            mutationNoiseScale: 0.01,
            accepted: false,
            rejectionReasons: ["minimum-incumbent-improvement"],
            createdAt: Date(timeIntervalSince1970: 1_778_112_000)
        ),
        to: evolutionRoot.appendingPathComponent("generations.jsonl")
    )

    let state = try LearningCampaignRunStore().load(from: root)

    #expect(state.primaryFailureReason == "generation:seed-1:g0: minimum-incumbent-improvement")
    #expect(state.failureReasons.contains("generation:seed-1:g0: minimum-incumbent-improvement"))
    #expect(state.failureReasons.contains("status: failed"))
    #expect(state.failureReasons.contains("event:2026-05-07T00:01:02Z: validation-failed"))
    #expect(state.failureReasons.contains("exitCode: 1"))
    #expect(state.diagnosticText.contains("failureReasons:"))
    #expect(state.diagnosticText.contains("accepted-checkpoint-missing"))
}

@Test func learningCampaignRunStoreExplainsValidRunRejectedByAcceptedCheckpointGate() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-campaign-accepted-checkpoint-rejected-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    try writeJSON(makePlan(root: root), to: root.appendingPathComponent("learning-campaign-plan.json"))
    try writeJSON(
        LearningCampaignStatus(
            status: "succeeded",
            exitCode: 0,
            startedAt: "2026-05-07T00:00:00Z",
            finishedAt: "2026-05-07T00:01:00Z"
        ),
        to: root.appendingPathComponent("campaign-status.json")
    )
    try writeJSON(
        LearningCampaignSummary(
            artifactRoot: root.path,
            seedCount: 1,
            acceptedCount: 0,
            finalCheckpoint: "",
            runs: []
        ),
        to: root.appendingPathComponent("learning-campaign-summary.json")
    )

    let evolutionRoot = root
        .appendingPathComponent("seeds", isDirectory: true)
        .appendingPathComponent("seed-1", isDirectory: true)
        .appendingPathComponent("evolution", isDirectory: true)
    try writeRejectedEvolutionArtifact(to: evolutionRoot)

    let state = try LearningCampaignRunStore().load(from: root)

    #expect(state.acceptedCheckpoints.count == 1)
    #expect(state.acceptedCheckpoints.first?.accepted == false)
    #expect(state.primaryFailureReason == "accepted-checkpoint:seed-1: dedicated-acceptance-required")
    #expect(state.failureReasons.contains("No checkpoint was accepted by the gate."))
    #expect(state.diagnosticText.contains("accepted-checkpoint:seed-1"))
    #expect(state.diagnosticText.contains("incumbent-improvement-below-min"))
}

@Test func learningCampaignRunStoreRejectsStandaloneAcceptedCheckpointWithoutValidatedEvolutionArtifact() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-campaign-standalone-accepted-checkpoint-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    try writeJSON(makePlan(root: root), to: root.appendingPathComponent("learning-campaign-plan.json"))
    let evolutionRoot = root
        .appendingPathComponent("seeds", isDirectory: true)
        .appendingPathComponent("seed-1", isDirectory: true)
        .appendingPathComponent("evolution", isDirectory: true)
    try FileManager.default.createDirectory(at: evolutionRoot, withIntermediateDirectories: true)
    try writeJSON(
        EvolutionAcceptedCheckpointDecision(
            runID: "run-1",
            terminalState: .completed,
            accepted: false,
            candidateID: nil,
            checkpointID: nil,
            checkpointURL: nil,
            scalarFitness: nil,
            bestCandidateID: "g12-c7",
            bestCheckpointID: "checkpoint-g12-c7",
            bestCheckpointURL: URL(fileURLWithPath: "/tmp/checkpoint-g12-c7", isDirectory: true),
            bestFitness: -287.3,
            incumbentCandidateID: "parent",
            incumbentFitness: -287.3,
            bestVsIncumbentDelta: 0,
            minimumImprovementOverIncumbent: 0.001,
            publishMetricRegressions: [],
            reasons: ["incumbent-improvement-below-min:g12-c7:-287.3--287.3<0.001"]
        ),
        to: evolutionRoot.appendingPathComponent(EvolutionAcceptedCheckpointDecision.fileName)
    )

    do {
        _ = try LearningCampaignRunStore().load(from: root)
        Issue.record("Expected standalone accepted checkpoint to fail without a validated evolution artifact.")
    } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError.missingEvolutionArtifact(let fileName) {
        #expect(fileName == EvolutionRunArtifactContract.fileName)
    }
}

@Test func learningCampaignRunStoreExplainsCancelledPartialEvolutionAsCancellation() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-campaign-cancelled-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    try writeJSON(makeFiveGenerationPlan(root: root), to: root.appendingPathComponent("learning-campaign-plan.json"))
    try writeJSON(
        LearningCampaignStatus(
            status: "cancelled",
            exitCode: 130,
            startedAt: "2026-05-07T00:00:00Z",
            finishedAt: "2026-05-07T00:02:00Z"
        ),
        to: root.appendingPathComponent("campaign-status.json")
    )
    try writeJSON(
        LearningCampaignSummary(
            artifactRoot: root.path,
            seedCount: 1,
            acceptedCount: 0,
            finalCheckpoint: "",
            runs: [
                LearningCampaignSeedRunSummary(
                    seed: "seed-1",
                    terminalState: "cancelled",
                    accepted: false,
                    acceptedCandidateID: nil,
                    acceptedCheckpointURL: nil,
                    incumbentCandidateID: nil,
                    incumbentFitness: nil,
                    bestCandidateID: "g6-c23",
                    bestFitness: -289.763,
                    bestVsIncumbentDelta: nil,
                    bestTaskPassRate: 0,
                    bestHoldTimeRatio: 0,
                    bestAltitudeErrorRatio: 7.37,
                    bestSafetyViolationRate: 0,
                    bestRewardAverage: -116.034,
                    gateNearestCandidateID: "g6-c23",
                    gateNearestFitness: -289.763,
                    gateNearestTaskPassRate: 0,
                    gateNearestHoldTimeRatio: 0,
                    gateNearestAltitudeErrorRatio: 7.37,
                    gateNearestSafetyViolationRate: 0,
                    gateNearestRewardAverage: -116.034,
                    fitnessCount: 168,
                    reasonCount: 168,
                    evaluationTraceCount: 168,
                    overlappedEvaluation: true
                )
            ]
        ),
        to: root.appendingPathComponent("learning-campaign-summary.json")
    )
    try writeValidationReceipt(
        root: root,
        valid: false,
        issues: [
            LearningCampaignValidationIssue(
                code: "invalid-seed-evolution-artifact",
                detail: "seed=1 error=missingCandidateFitness(\"g7-c0\")"
            )
        ]
    )
    try writeLine(
        LearningCampaignProgressEvent(
            event: "campaign-finished",
            timestamp: Date(timeIntervalSince1970: 1_778_112_122),
            status: "cancelled",
            exitCode: 130
        ),
        to: root.appendingPathComponent("progress.jsonl")
    )

    let state = try LearningCampaignRunStore().load(from: root)

    #expect(state.diagnosis.severity == .warning)
    #expect(state.primaryFailureReason == "Campaign was cancelled before completion.")
    #expect(state.failureReasons.contains("status: cancelled"))
    #expect(state.failureReasons.contains("exitCode: 130"))
    #expect(state.failureReasons.contains("No checkpoint was accepted by the gate."))
    #expect(state.diagnosticText.contains("recordedStrictValidationIssues:"))
    #expect(state.diagnosticText.contains("missingCandidateFitness"))
    #expect(state.primaryFailureReason?.contains("missingCandidateFitness") == false)
}

@Test func learningCampaignRunStoreLoadsRawEvolutionArtifactsForFiveGenerationPreview() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-raw-evolution-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeJSON(
        EvolutionRunManifest(
            runID: "raw-evolution",
            taskID: "lift",
            configHash: "raw",
            policyID: "manasMLX",
            populationSize: 8,
            generationCount: 5,
            eliteCount: 2,
            workerCount: 1,
            candidateEvaluationConcurrency: 8,
            searchStrategy: .qualityDiversity,
            mutationRate: 0.08,
            mutationNoiseScale: 0.01,
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2),
            terminalState: .completed
        ),
        to: root.appendingPathComponent("evolution-manifest.json")
    )
    for generation in 0..<5 {
        let candidateID = "g\(generation)-c7"
        try writeLine(
            PopulationGenerationRecord(
                runID: "raw-evolution",
                generationIndex: generation,
                candidateCount: 8,
                evaluatedCandidateCount: 8,
                eliteCandidateIDs: ["g\(generation)-c7", "g\(generation)-c6"],
                bestCandidateID: "g\(generation)-c7",
                bestFitness: Double(generation),
                incumbentCandidateID: "g0-c0",
                incumbentFitness: 0,
                bestVsIncumbentDelta: Double(generation),
                mutationRate: 0.08,
                mutationNoiseScale: 0.01,
                accepted: true,
                rejectionReasons: [],
                createdAt: Date(timeIntervalSince1970: 10 + Double(generation))
            ),
            to: root.appendingPathComponent("generations.jsonl")
        )
        try writeLine(
            GenomeCandidate(
                runID: "raw-evolution",
                generationIndex: generation,
                candidateID: candidateID,
                genomeID: "genome-\(candidateID)",
                parentCandidateIDs: generation == 0 ? [] : ["g\(generation - 1)-c7", "g\(generation - 1)-c6"],
                mutationRate: 0.08,
                mutationNoiseScale: 0.01,
                mutationSummary: generation == 0 ? "incumbent-parent" : "gaussian-crossover-mutation"
            ),
            to: root.appendingPathComponent("candidates.jsonl")
        )
        try writeLine(
            FitnessSummary(
                runID: "raw-evolution",
                generationIndex: generation,
                candidateID: candidateID,
                taskID: "lift",
                scalarFitness: Double(generation),
                rewardAverage: Double(generation),
                taskPassRate: 1,
                safetyViolationRate: 0
            ),
            to: root.appendingPathComponent("fitness.jsonl")
        )
        try writeLine(
            EvolutionCandidateEvaluationTrace(
                runID: "raw-evolution",
                generationIndex: generation,
                candidateID: candidateID,
                requestedConcurrency: 8,
                activeEvaluationCountAtStart: 8,
                startedAt: Date(timeIntervalSince1970: 20 + Double(generation)),
                completedAt: Date(timeIntervalSince1970: 21 + Double(generation))
            ),
            to: root.appendingPathComponent("evaluation-trace.jsonl")
        )
    }

    let state = try LearningCampaignRunStore().load(from: root)

    #expect(state.statusLabel == "completed")
    #expect(state.plan == nil)
    #expect(state.evolutionManifest?.populationSize == 8)
    #expect(state.task == "lift")
    #expect(state.plannedGenerationCount == 5)
    #expect(state.plannedCandidateEvaluationCount == 40)
    #expect(state.generations.count == 5)
    #expect(state.candidates.count == 5)
    #expect(state.acceptedCount == 0)
    #expect(state.maxRequestedCandidateConcurrency == 8)
    #expect(state.maxActiveCandidateEvaluations == 8)
    #expect(state.candidateEvaluationCount == 5)
    #expect(state.actualParallelismLabel == "8/8 active")
    #expect(state.averageCandidateEvaluationDurationSeconds == 1)
    #expect(state.candidates(seed: "evolution", generationIndex: 4).first?.parentCandidateIDs == ["g3-c7", "g3-c6"])
    #expect(state.latestGenerations.first?.seed == "evolution")
    #expect(state.latestGenerations.first?.generationIndex == 4)
}

@Test func learningCampaignRunStoreRejectsInvalidVectorizedBatchArtifactThroughReader() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-ui-invalid-vectorized-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeJSON(makePlan(root: root), to: root.appendingPathComponent("learning-campaign-plan.json"))

    let vectorizedRoot = root.appendingPathComponent("vectorized-evaluations", isDirectory: true)
    try FileManager.default.createDirectory(at: vectorizedRoot, withIntermediateDirectories: true)
    try writeJSON(
        UncheckedLearningCampaignVectorizedEvaluationArtifact(
            artifact: makeVectorizedEvaluationArtifact(),
            schemaVersion: 0
        ),
        to: vectorizedRoot.appendingPathComponent(ManasMLXVectorizedEvaluationArtifact.fileName)
    )

    do {
        _ = try LearningCampaignRunStore().load(from: root)
        Issue.record("Expected invalid vectorized batch artifact to fail through the UI artifact reader.")
    } catch ManasMLXVectorizedEvaluationArtifactValidator.ValidationError.unsupportedSchemaVersion(let version) {
        #expect(version == 0)
    }
}

private func makePlan(root: URL) -> LearningCampaignPlan {
    LearningCampaignPlan(
        artifactRoot: root.path,
        task: "singleLift",
        searchSuites: ["6", "7"],
        searchEpisodes: 1,
        acceptanceSuites: ["6", "7"],
        acceptanceEpisodes: 1,
        workers: 2,
        population: 4,
        generations: 2,
        eliteCount: 1,
        candidateEvaluationConcurrency: 2,
        cutPeriodSteps: 2,
        seeds: ["seed-1"],
        sourceCheckpoint: nil,
        robotManifest: nil,
        variation: "low-noise",
        searchStrategy: "genetic",
        mutationRate: 0.02,
        mutationNoiseScale: 0.01,
        bootstrapSuite: "6",
        bootstrapEpisodes: 1,
        bootstrapSequence: 8,
        bootstrapEpochs: 1,
        bootstrapMaxBatches: 1,
        bootstrapLearningRate: 0.001,
        bootstrapRepairAttempts: nil,
        verifyParentTask: true,
        resumeEnabled: false,
        resourceSampleSeconds: nil,
        artifactRetentionPolicy: .compact,
        availableDiskBytes: 1_000_000_000,
        requiredDiskBytes: 1_000_000,
        plannedCandidateEvaluations: 8,
        plannedRegressionRollouts: 8,
        plannedRegressionEpisodes: 8
    )
}

private func makeFiveGenerationPlan(root: URL) -> LearningCampaignPlan {
    LearningCampaignPlan(
        artifactRoot: root.path,
        task: "lift",
        searchSuites: ["6"],
        searchEpisodes: 1,
        acceptanceSuites: ["6"],
        acceptanceEpisodes: 1,
        workers: 1,
        population: 8,
        generations: 5,
        eliteCount: 2,
        candidateEvaluationConcurrency: 8,
        cutPeriodSteps: 2,
        seeds: ["seed-1"],
        sourceCheckpoint: nil,
        robotManifest: nil,
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
        resumeEnabled: false,
        resourceSampleSeconds: nil,
        artifactRetentionPolicy: .full,
        availableDiskBytes: 1_000_000_000,
        requiredDiskBytes: 1_000_000,
        plannedCandidateEvaluations: 40,
        plannedRegressionRollouts: 40,
        plannedRegressionEpisodes: 40
    )
}

private func writeRejectedEvolutionArtifact(to directory: URL) throws {
    let runID = "run-1"
    let bestCandidateID = "g12-c7"
    let incumbentCandidateID = "parent"
    let checkpointURL = URL(fileURLWithPath: "/tmp/checkpoint-g12-c7", isDirectory: true)
    let manifest = EvolutionRunManifest(
        runID: runID,
        taskID: "singleLift",
        configHash: "config-hash",
        policyID: "manasMLX",
        populationSize: 2,
        generationCount: 13,
        eliteCount: 1,
        workerCount: 1,
        candidateEvaluationConcurrency: 2,
        startedAt: Date(timeIntervalSince1970: 1),
        completedAt: Date(timeIntervalSince1970: 2),
        terminalState: .completed
    )
    let generation = PopulationGenerationRecord(
        runID: runID,
        generationIndex: 12,
        candidateCount: 2,
        evaluatedCandidateCount: 2,
        eliteCandidateIDs: [bestCandidateID],
        bestCandidateID: bestCandidateID,
        bestFitness: -287.3,
        incumbentCandidateID: incumbentCandidateID,
        incumbentFitness: -287.3,
        bestVsIncumbentDelta: 0,
        minimumImprovementOverIncumbent: 0.001,
        incumbentImproved: false,
        mutationRate: 0.08,
        mutationNoiseScale: 0.01,
        accepted: false,
        rejectionReasons: [],
        createdAt: Date(timeIntervalSince1970: 2)
    )
    let incumbent = GenomeCandidate(
        runID: runID,
        generationIndex: 0,
        candidateID: incumbentCandidateID,
        genomeID: "genome-parent",
        checkpointID: "checkpoint-parent",
        checkpointURL: URL(fileURLWithPath: "/tmp/checkpoint-parent", isDirectory: true),
        mutationRate: 0,
        mutationNoiseScale: 0,
        isIncumbent: true
    )
    let best = GenomeCandidate(
        runID: runID,
        generationIndex: 12,
        candidateID: bestCandidateID,
        genomeID: "genome-g12-c7",
        parentCandidateIDs: [incumbentCandidateID],
        checkpointID: "checkpoint-g12-c7",
        checkpointURL: checkpointURL,
        mutationRate: 0.08,
        mutationNoiseScale: 0.01
    )
    let incumbentFitness = FitnessSummary(
        runID: runID,
        generationIndex: 0,
        candidateID: incumbentCandidateID,
        taskID: "singleLift",
        scalarFitness: -287.3,
        rewardAverage: -287.3,
        taskPassRate: 1,
        safetyViolationRate: 0
    )
    let bestFitness = FitnessSummary(
        runID: runID,
        generationIndex: 12,
        candidateID: bestCandidateID,
        taskID: "singleLift",
        scalarFitness: -287.3,
        rewardAverage: -287.3,
        taskPassRate: 1,
        safetyViolationRate: 0
    )
    try EvolutionArtifactWriter().write(
        manifest: manifest,
        generations: [generation],
        candidates: [incumbent, best],
        fitness: [incumbentFitness, bestFitness],
        eliteArchive: EvolutionEliteArchive(
            runID: runID,
            eliteCandidateIDs: [bestCandidateID],
            bestCandidateID: bestCandidateID,
            bestFitness: -287.3
        ),
        qualityDiversityArchive: EvolutionQualityDiversityArchive(
            runID: runID,
            descriptorKeys: ["taskPassRate"],
            cells: [
                EvolutionQualityDiversityCell(
                    cellID: "taskPassRate=1",
                    candidateID: bestCandidateID,
                    generationIndex: 12,
                    fitness: -287.3,
                    behaviorDescriptor: ["taskPassRate": 1]
                )
            ]
        ),
        lineage: [
            EvolutionLineageRecord(
                runID: runID,
                generationIndex: 0,
                candidateID: incumbentCandidateID,
                genomeID: "genome-parent",
                parentCandidateIDs: []
            ),
            EvolutionLineageRecord(
                runID: runID,
                generationIndex: 12,
                candidateID: bestCandidateID,
                genomeID: "genome-g12-c7",
                parentCandidateIDs: [incumbentCandidateID]
            )
        ],
        evaluationTraces: [
            EvolutionCandidateEvaluationTrace(
                runID: runID,
                generationIndex: 0,
                candidateID: incumbentCandidateID,
                requestedConcurrency: 2,
                activeEvaluationCountAtStart: 1,
                startedAt: Date(timeIntervalSince1970: 1),
                completedAt: Date(timeIntervalSince1970: 2)
            ),
            EvolutionCandidateEvaluationTrace(
                runID: runID,
                generationIndex: 12,
                candidateID: bestCandidateID,
                requestedConcurrency: 2,
                activeEvaluationCountAtStart: 2,
                startedAt: Date(timeIntervalSince1970: 1),
                completedAt: Date(timeIntervalSince1970: 2)
            )
        ],
        acceptanceEvaluations: [],
        to: directory
    )
}

private func makeVectorizedEvaluationArtifact() throws -> ManasMLXVectorizedEvaluationArtifact {
    let quality = try VectorizedTaskQualitySummary(
        profileID: "attitude",
        task: "attitude",
        scenarioSuiteID: "6",
        scenarioID: "ATT-1",
        seed: 1,
        passed: true,
        failureReasons: [],
        evaluatorID: "test-quality",
        metrics: ["rewardAverage": 1]
    )
    let summary = try VectorizedCandidateRolloutSummary(
        candidateID: "candidate-a",
        rewardAverage: 1,
        fitness: 1,
        taskPassRate: 1,
        safetyViolationRate: 0,
        rolloutCount: 1,
        taskQuality: [quality]
    )
    let batchSpec = try VectorizedTrainingBatchSpec(
        populationSize: 1,
        worldCount: 1,
        rolloutHorizon: 20_000,
        historyLength: 1,
        observationDimension: 16,
        actionDimension: 4,
        actionEncoding: .ctbr,
        executionMode: .sharedWorld,
        requiresAccelerator: .metal
    )
    return ManasMLXVectorizedEvaluationArtifact(
        evaluatorID: "test-vectorized-evaluator",
        runID: "test-run",
        taskID: "attitude",
        profileID: "attitude",
        generationIndex: 0,
        candidateIDs: ["candidate-a"],
        batchSpec: batchSpec,
        requestedCandidateCount: 1,
        evaluatedCandidateCount: 1,
        startedAt: Date(timeIntervalSince1970: 0),
        completedAt: Date(timeIntervalSince1970: 1),
        elapsedSeconds: 1,
        acceleratorDevice: "metal",
        policyExecutionMode: "mlx-stacked-population-temporal-ctbr",
        observationExecutionMode: "mlx-tensor-ctbr-observation-bridge-v1",
        worldExecutionMode: "mlx-tensor-lift-world-v1",
        worldActiveActionDimension: 4,
        evaluationFidelity: .fullScenario,
        workPhase: .candidateGate,
        worldExecutionRequirement: .preferAcceleratorSharedWorld,
        summaries: [summary]
    )
}

private struct UncheckedLearningCampaignVectorizedEvaluationArtifact: Encodable {
    let schemaVersion: Int
    let evaluatorID: String
    let runID: String
    let taskID: String
    let profileID: String
    let generationIndex: Int
    let candidateIDs: [String]
    let batchSpec: VectorizedTrainingBatchSpec
    let requestedCandidateCount: Int
    let evaluatedCandidateCount: Int
    let startedAt: Date
    let completedAt: Date
    let elapsedSeconds: Double
    let acceleratorDevice: String
    let policyExecutionMode: String
    let observationExecutionMode: String
    let worldExecutionMode: String
    let worldActiveActionDimension: Int
    let evaluationFidelity: TrainingEvaluationFidelity
    let workPhase: TrainingWorkPhase
    let worldExecutionRequirement: VectorizedWorldExecutionRequirement
    let summaries: [VectorizedCandidateRolloutSummary]

    init(
        artifact: ManasMLXVectorizedEvaluationArtifact,
        schemaVersion: Int
    ) {
        self.schemaVersion = schemaVersion
        evaluatorID = artifact.evaluatorID
        runID = artifact.runID
        taskID = artifact.taskID
        profileID = artifact.profileID
        generationIndex = artifact.generationIndex
        candidateIDs = artifact.candidateIDs
        batchSpec = artifact.batchSpec
        requestedCandidateCount = artifact.requestedCandidateCount
        evaluatedCandidateCount = artifact.evaluatedCandidateCount
        startedAt = artifact.startedAt
        completedAt = artifact.completedAt
        elapsedSeconds = artifact.elapsedSeconds
        acceleratorDevice = artifact.acceleratorDevice
        policyExecutionMode = artifact.policyExecutionMode
        observationExecutionMode = artifact.observationExecutionMode
        worldExecutionMode = artifact.worldExecutionMode
        worldActiveActionDimension = artifact.worldActiveActionDimension
        evaluationFidelity = artifact.evaluationFidelity
        workPhase = artifact.workPhase
        worldExecutionRequirement = artifact.worldExecutionRequirement
        summaries = artifact.summaries
    }
}

private func writeValidationReceipt(
    root: URL,
    valid: Bool = true,
    issues: [LearningCampaignValidationIssue] = [],
    policy: LearningCampaignValidationPolicy = .strict
) throws {
    let snapshot = try LearningCampaignValidationInputSnapshotter().snapshot(at: root)
    let integrity = LearningCampaignValidationReceiptIntegrity()
    let receipt = try integrity.receipt(content: LearningCampaignValidationContent(
        timestamp: "2026-05-07T00:00:01Z",
        artifactRoot: root.path,
        validator: .current,
        policy: policy,
        inputSnapshot: snapshot,
        valid: valid,
        issueCount: issues.count,
        issues: issues
    ))
    _ = try LearningCampaignValidationReceiptStore(integrity: integrity).write(
        receipt,
        to: root
    )
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    try data.write(to: url, options: .atomic)
}

private func writeLine<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    let line = String(decoding: data, as: UTF8.self) + "\n"
    if FileManager.default.fileExists(atPath: url.path) {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
        try handle.close()
    } else {
        try line.write(to: url, atomically: true, encoding: .utf8)
    }
}
