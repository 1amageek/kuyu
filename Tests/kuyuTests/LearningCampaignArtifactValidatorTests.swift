import Foundation
import KuyuMLX
import KuyuScenarios
import KuyuTraining
import Testing

@Test func learningCampaignArtifactValidatorAcceptsCompleteCampaign() throws {
    let root = try makeLearningCampaignArtifactRoot()

    let validation = try LearningCampaignArtifactValidator().validate(artifactRoot: root)

    #expect(validation.valid)
    #expect(validation.issueCount == 0)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("learning-campaign-validation.json").path))
}

@Test func learningCampaignArtifactValidatorRejectsFailedInitialParentEvaluation() throws {
    let root = try makeLearningCampaignArtifactRoot()
    let checkpointRoot = root.appendingPathComponent("bootstrap-checkpoint", isDirectory: true)
    try writeCheckpointEvaluation(
        root: root,
        label: "initial-parent",
        task: "lift",
        checkpointRoot: checkpointRoot,
        passed: false
    )

    do {
        _ = try LearningCampaignArtifactValidator().validate(artifactRoot: root)
        Issue.record("Expected failed initial parent evaluation to reject.")
    } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
        #expect(!validation.valid)
        #expect(validation.issues.contains { $0.code == "parent-task-evaluation-failed" })
    }
}

@Test func learningCampaignArtifactValidatorRejectsIncompleteFinalCheckpoint() throws {
    let root = try makeLearningCampaignArtifactRoot()
    try FileManager.default.removeItem(
        at: root
            .appendingPathComponent("bootstrap-checkpoint", isDirectory: true)
            .appendingPathComponent("reflex.safetensors")
    )

    do {
        _ = try LearningCampaignArtifactValidator().validate(artifactRoot: root)
        Issue.record("Expected campaign validation to fail.")
    } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
        #expect(!validation.valid)
        #expect(validation.issues.contains { $0.code == "incomplete-final-checkpoint" })
    }
}

@Test func learningCampaignArtifactValidatorRejectsFinalCheckpointMismatch() throws {
    let root = try makeLearningCampaignArtifactRoot()
    let unrelatedCheckpoint = root.appendingPathComponent("unrelated-checkpoint", isDirectory: true)
    try FileManager.default.createDirectory(at: unrelatedCheckpoint, withIntermediateDirectories: true)
    try write("{}", to: unrelatedCheckpoint.appendingPathComponent("model.json"))
    try write("core", to: unrelatedCheckpoint.appendingPathComponent("core.safetensors"))
    try write("reflex", to: unrelatedCheckpoint.appendingPathComponent("reflex.safetensors"))
    try rewriteSummaryFinalCheckpoint(root: root, finalCheckpoint: unrelatedCheckpoint.path)

    do {
        _ = try LearningCampaignArtifactValidator().validate(artifactRoot: root)
        Issue.record("Expected campaign validation to fail.")
    } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
        #expect(!validation.valid)
        #expect(validation.issues.contains { $0.code == "final-checkpoint-mismatch" })
    }
}

@Test func learningCampaignArtifactValidatorRejectsMissingSeedEvolutionArtifact() throws {
    let root = try makeLearningCampaignArtifactRoot()
    try FileManager.default.removeItem(
        at: root
            .appendingPathComponent("seeds", isDirectory: true)
            .appendingPathComponent("seed-1", isDirectory: true)
            .appendingPathComponent("evolution", isDirectory: true)
            .appendingPathComponent("fitness.jsonl")
    )

    do {
        _ = try LearningCampaignArtifactValidator().validate(artifactRoot: root)
        Issue.record("Expected campaign validation to fail.")
    } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
        #expect(!validation.valid)
        #expect(validation.issues.contains { $0.code == "missing-seed-evolution-artifact" })
    }
}

@Test func learningCampaignArtifactValidatorRejectsCorruptSeedEvolutionArtifact() throws {
    let root = try makeLearningCampaignArtifactRoot()
    try write(
        "{}",
        to: root
            .appendingPathComponent("seeds", isDirectory: true)
            .appendingPathComponent("seed-1", isDirectory: true)
            .appendingPathComponent("evolution", isDirectory: true)
            .appendingPathComponent("fitness.jsonl")
    )

    do {
        _ = try LearningCampaignArtifactValidator().validate(artifactRoot: root)
        Issue.record("Expected campaign validation to fail.")
    } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
        #expect(!validation.valid)
        #expect(validation.issues.contains { $0.code == "invalid-seed-evolution-artifact" })
    }
}

@Test func learningCampaignArtifactValidatorRejectsMissingRootWithTypedIssue() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("missing-kuyu-learning-campaign-\(UUID().uuidString)", isDirectory: true)

    do {
        _ = try LearningCampaignArtifactValidator().validate(artifactRoot: root)
        Issue.record("Expected campaign validation to fail.")
    } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
        #expect(!validation.valid)
        #expect(validation.issues.contains { $0.code == "missing-artifact-root" })
    }
}

@Test func learningCampaignArtifactValidatorCanValidateRunningCampaignShape() throws {
    let root = try makeLearningCampaignArtifactRoot()
    try FileManager.default.removeItem(at: root.appendingPathComponent("campaign-status.json"))
    try write("""
    {"event":"campaign-started","timestamp":"2026-05-06T00:00:00Z"}
    {"event":"summary-written","timestamp":"2026-05-06T00:01:00Z"}
    """, to: root.appendingPathComponent("progress.jsonl"))

    let validation = try LearningCampaignArtifactValidator().validate(
        artifactRoot: root,
        allowRunning: true
    )

    #expect(validation.valid)
}

@Test func learningCampaignArtifactValidatorRejectsRunningCampaignInStrictMode() throws {
    let root = try makeLearningCampaignArtifactRoot()
    try FileManager.default.removeItem(at: root.appendingPathComponent("campaign-status.json"))

    do {
        _ = try LearningCampaignArtifactValidator().validate(artifactRoot: root)
        Issue.record("Expected strict campaign validation to fail.")
    } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
        #expect(!validation.valid)
        #expect(validation.issues.contains { $0.code == "missing-json" && $0.detail == "campaign-status.json" })
    }
}

@Test func learningCampaignArtifactValidatorRejectsMissingParentTaskEvaluation() throws {
    let root = try makeLearningCampaignArtifactRoot()
    try FileManager.default.removeItem(
        at: root
            .appendingPathComponent("checkpoint-evaluations", isDirectory: true)
            .appendingPathComponent("initial-parent", isDirectory: true)
            .appendingPathComponent("checkpoint-evaluation.json")
    )

    do {
        _ = try LearningCampaignArtifactValidator().validate(artifactRoot: root)
        Issue.record("Expected parent task evaluation validation to fail.")
    } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
        #expect(!validation.valid)
        #expect(validation.issues.contains { $0.code == "missing-parent-task-evaluation" })
    }
}

@Test func learningCampaignArtifactValidatorRejectsMissingParentTaskRegression() throws {
    let root = try makeLearningCampaignArtifactRoot()
    try FileManager.default.removeItem(
        at: root
            .appendingPathComponent("checkpoint-regressions", isDirectory: true)
            .appendingPathComponent("initial-parent", isDirectory: true)
            .appendingPathComponent("kuyu-regression-summary.json")
    )

    do {
        _ = try LearningCampaignArtifactValidator().validate(artifactRoot: root)
        Issue.record("Expected parent task regression validation to fail.")
    } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
        #expect(!validation.valid)
        #expect(validation.issues.contains { $0.code == "missing-parent-task-regression" })
    }
}

@Test func learningCampaignArtifactValidatorRejectsFailedAcceptedParentTaskEvaluation() throws {
    let root = try makeLearningCampaignArtifactRoot()
    let checkpointRoot = root.appendingPathComponent("bootstrap-checkpoint", isDirectory: true)
    try writeCheckpointEvaluation(
        root: root,
        label: "seed-1-accepted",
        task: "lift",
        checkpointRoot: checkpointRoot,
        passed: false
    )

    do {
        _ = try LearningCampaignArtifactValidator().validate(artifactRoot: root)
        Issue.record("Expected failed parent task evaluation validation to fail.")
    } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
        #expect(!validation.valid)
        #expect(validation.issues.contains { $0.code == "parent-task-evaluation-failed" })
    }
}

@Test func learningCampaignArtifactValidatorRejectsMissingAcceptedParentTaskQuality() throws {
    let root = try makeLearningCampaignArtifactRoot()
    let checkpointRoot = root.appendingPathComponent("bootstrap-checkpoint", isDirectory: true)
    try writeCheckpointEvaluation(
        root: root,
        label: "seed-1-accepted",
        task: "lift",
        checkpointRoot: checkpointRoot,
        passed: true,
        includesQualitySummary: false
    )

    do {
        _ = try LearningCampaignArtifactValidator().validate(artifactRoot: root)
        Issue.record("Expected missing checkpoint task quality validation to fail.")
    } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
        #expect(!validation.valid)
        #expect(validation.issues.contains { $0.code == "parent-task-evaluation-missing-expected-task-quality" })
    }
}

private func makeLearningCampaignArtifactRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-learning-campaign-artifact-\(UUID().uuidString)", isDirectory: true)
    let evolutionRoot = root
        .appendingPathComponent("seeds", isDirectory: true)
        .appendingPathComponent("seed-1", isDirectory: true)
        .appendingPathComponent("evolution", isDirectory: true)
    let checkpointRoot = root.appendingPathComponent("bootstrap-checkpoint", isDirectory: true)
    try FileManager.default.createDirectory(at: evolutionRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: checkpointRoot, withIntermediateDirectories: true)

    try write("""
    {
      "artifactRoot": "\(root.path)",
      "availableDiskBytes": 1000000000,
      "bootstrapEpisodes": 1,
      "bootstrapEpochs": 1,
      "bootstrapLearningRate": 0.001,
      "bootstrapMaxBatches": 1,
      "bootstrapRepairAttempts": 0,
      "bootstrapSequence": 16,
      "bootstrapSuite": "6",
      "candidateEvaluationConcurrency": 2,
      "eliteCount": 1,
      "episodes": 1,
      "generations": 1,
      "modelDescriptor": null,
      "mutationNoiseScale": 0.01,
      "mutationRate": 0.08,
      "plannedCandidateEvaluations": 2,
      "plannedRegressionEpisodes": 4,
      "plannedRegressionRollouts": 4,
      "population": 2,
      "requiredDiskBytes": 1,
      "resourceSampleSeconds": 1,
      "resumeEnabled": false,
      "searchStrategy": "qualityDiversity",
      "seeds": ["1"],
      "sourceCheckpoint": null,
      "suites": ["6"],
      "task": "lift",
      "variation": "gaussian",
      "verifyParentTask": true,
      "workers": 1
    }
    """, to: root.appendingPathComponent("learning-campaign-plan.json"))
    try write("""
    {
      "configuration": "Debug",
      "derivedData": "/tmp/DerivedData",
      "destination": "platform=macOS",
      "host": "test-host",
      "lockPath": "/tmp/kuyu.lock",
      "machine": "arm64",
      "platform": "macOS",
      "repositories": [
        {"branch": "main", "dirty": false, "head": "abc", "path": "\(root.path)"}
      ],
      "swiftVersion": "Swift test",
      "timestamp": "2026-05-06T00:00:00Z",
      "xcodebuildVersion": "Xcode test"
    }
    """, to: root.appendingPathComponent("learning-campaign-environment.json"))
    try write("""
    {
      "exitCode": 0,
      "finishedAt": "2026-05-06T00:01:00Z",
      "startedAt": "2026-05-06T00:00:00Z",
      "status": "succeeded"
    }
    """, to: root.appendingPathComponent("campaign-status.json"))
    try write("""
    {"event":"campaign-started","timestamp":"2026-05-06T00:00:00Z"}
    {"event":"campaign-finished","exitCode":0,"status":"succeeded","timestamp":"2026-05-06T00:01:00Z"}
    """, to: root.appendingPathComponent("progress.jsonl"))
    try write("""
    {"artifactRootFreeBytes":1000000,"artifactRootUsedBytes":1,"loadAverage1m":1,"timestamp":"2026-05-06T00:00:00Z"}
    """, to: root.appendingPathComponent("resource-samples.jsonl"))
    try write("""
    {
      "acceptedCount": 1,
      "artifactRoot": "\(root.path)",
      "finalCheckpoint": "\(checkpointRoot.path)",
      "runs": [
        {
          "accepted": true,
          "acceptedCandidateID": "candidate-1",
          "acceptedCheckpointURL": "\(checkpointRoot.path)",
          "bestCandidateID": "candidate-1",
          "bestFitness": 2.0,
          "bestAltitudeErrorRatio": 0.0,
          "bestHoldTimeRatio": 1.0,
          "bestRewardAverage": 2.0,
          "bestSafetyViolationRate": 0.0,
          "bestTaskPassRate": 1.0,
          "bestVsIncumbentDelta": 1.0,
          "gateNearestCandidateID": "candidate-1",
          "gateNearestFitness": 2.0,
          "gateNearestAltitudeErrorRatio": 0.0,
          "gateNearestHoldTimeRatio": 1.0,
          "gateNearestRewardAverage": 2.0,
          "gateNearestSafetyViolationRate": 0.0,
          "gateNearestTaskPassRate": 1.0,
          "evaluationTraceCount": 2,
          "fitnessCount": 2,
          "incumbentCandidateID": "candidate-0",
          "incumbentFitness": 1.0,
          "overlappedEvaluation": true,
          "reasonCount": 0,
          "seed": "1",
          "terminalState": "completed"
        }
      ],
      "seedCount": 1
    }
    """, to: root.appendingPathComponent("learning-campaign-summary.json"))

    try write("{}", to: checkpointRoot.appendingPathComponent("model.json"))
    try write("core", to: checkpointRoot.appendingPathComponent("core.safetensors"))
    try write("reflex", to: checkpointRoot.appendingPathComponent("reflex.safetensors"))
    try writeCheckpointEvaluation(
        root: root,
        label: "initial-parent",
        task: "lift",
        checkpointRoot: checkpointRoot,
        passed: true
    )
    try writeParentRegression(
        root: root,
        label: "initial-parent",
        task: "lift",
        checkpointRoot: checkpointRoot,
        passed: true
    )
    try writeCheckpointEvaluation(
        root: root,
        label: "seed-1-accepted",
        task: "lift",
        checkpointRoot: checkpointRoot,
        passed: true
    )
    try writeParentRegression(
        root: root,
        label: "seed-1-accepted",
        task: "lift",
        checkpointRoot: checkpointRoot,
        passed: true
    )
    try writeValidEvolutionArtifacts(evolutionRoot: evolutionRoot, checkpointRoot: checkpointRoot)
    return root
}

private func writeCheckpointEvaluation(
    root: URL,
    label: String,
    task: String,
    checkpointRoot: URL,
    passed: Bool,
    includesQualitySummary: Bool = true
) throws {
    let failures = passed ? "" : #""lift-unsettled""#
    let expectedQualityKeys = """
      [
        {
          "scenarioID": "\(task)-fixture",
          "seed": 1
        }
      ]
    """
    let qualitySummary = includesQualitySummary ? """
      [
        {
          "achievedHoldTime": 1.0,
          "evaluatorID": "ReferenceQuadrotorTaskQualityEvaluator",
          "failureReasons": [],
          "maxAltitudeErrorAfterWarmup": 0.0,
          "maxVerticalVelocityAfterWarmup": 0.0,
          "passed": true,
          "requiredHoldTime": 1.0,
          "scenarioID": "\(task)-fixture",
          "seed": 1,
          "targetZ": 1.0,
          "task": "\(task)",
          "tolerance": 0.1,
          "warmupTime": 0.0
        }
      ]
    """ : "[]"
    try write("""
    {
      "checkpointPath": "\(checkpointRoot.path)",
      "evaluationID": "eval-\(label)",
      "expectedQualityKeys": \(expectedQualityKeys),
      "failureReasons": [\(failures)],
      "policyPassed": \(passed),
      "policyScore": \(passed ? 1 : 0),
      "profileID": "\(task)-v1",
      "qualitySummary": \(qualitySummary),
      "scoreDeltaFromTeacher": 0,
      "schemaVersion": 2,
      "startedAt": "2026-05-06T00:00:00Z",
      "task": "\(task)",
      "teacherPassed": true,
      "teacherScore": 1
    }
    """, to: root
        .appendingPathComponent("checkpoint-evaluations", isDirectory: true)
        .appendingPathComponent(label, isDirectory: true)
        .appendingPathComponent("checkpoint-evaluation.json"))
}

private func writeParentRegression(
    root: URL,
    label: String,
    task: String,
    checkpointRoot: URL,
    passed: Bool
) throws {
    let quality = ReferenceQuadrotorTaskQualitySummary(
        task: task,
        scenarioID: "\(task)-regression-fixture",
        seed: 1,
        passed: passed,
        failureReasons: passed ? [] : ["lift-unsettled"],
        evaluatorID: "ReferenceQuadrotorTaskQualityEvaluator",
        targetZ: 1,
        tolerance: 0.1,
        warmupTime: 0,
        requiredHoldTime: 1,
        achievedHoldTime: passed ? 1 : 0,
        maxAltitudeErrorAfterWarmup: passed ? 0 : 1,
        maxVerticalVelocityAfterWarmup: 0
    )
    let entry = KuyuRegressionRolloutEntry(
        suite: 6,
        track: "longHorizonTask",
        policyID: "manasMLX-regression",
        episodeCount: 1,
        rewardSum: passed ? 1 : -1,
        rewardAverage: passed ? 1 : -1,
        doneCount: passed ? 1 : 0,
        truncatedCount: 0,
        failureCount: passed ? 0 : 1,
        cancelledCount: 0,
        failureReasons: passed ? [] : ["lift-unsettled"],
        taskPassCount: passed ? 1 : 0,
        taskFailureCount: passed ? 0 : 1,
        taskFailureReasons: passed ? [] : ["lift-unsettled"],
        taskQuality: [quality],
        workerSummaries: [
            KuyuRegressionWorkerSummary(
                workerIndex: 0,
                snapshotID: checkpointRoot.lastPathComponent,
                rolloutShardPath: nil,
                episodeCount: 1,
                rewardSum: passed ? 1 : -1,
                rewardAverage: passed ? 1 : -1,
                throughput: 1,
                doneCount: passed ? 1 : 0,
                truncatedCount: 0,
                failureCount: passed ? 0 : 1,
                cancelledCount: 0
            ),
        ],
        artifactPath: nil
    )
    let gateReport = KuyuRegressionGatePolicy.report(
        preflightFailure: nil,
        environmentTasks: [],
        rolloutSuites: [entry],
        failOnTruncation: false,
        minimumRewardAverage: nil,
        qualityGateTask: task
    )
    let summary = KuyuRegressionSummary(
        artifactRoot: root
            .appendingPathComponent("checkpoint-regressions", isDirectory: true)
            .appendingPathComponent(label, isDirectory: true)
            .path,
        startedAt: Date(timeIntervalSince1970: 1),
        controller: "ManasMLX",
        environmentController: "Teacher Baseline",
        snapshot: checkpointRoot.path,
        preflightPassed: true,
        preflightFailure: nil,
        environmentReady: true,
        environmentTasks: [],
        rolloutPassed: passed,
        rolloutSuites: [entry],
        gateReport: gateReport,
        allPassed: gateReport.accepted
    )
    let artifactRoot = root
        .appendingPathComponent("checkpoint-regressions", isDirectory: true)
        .appendingPathComponent(label, isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(summary).write(
        to: artifactRoot.appendingPathComponent("kuyu-regression-summary.json"),
        options: [.atomic]
    )
}

private func writeValidEvolutionArtifacts(evolutionRoot: URL, checkpointRoot: URL) throws {
    let runID = "campaign-seed-1"
    let startedAt = Date(timeIntervalSince1970: 1)
    let completedAt = Date(timeIntervalSince1970: 2)
    let manifest = EvolutionRunManifest(
        runID: runID,
        taskID: "lift",
        configHash: "config-hash",
        policyID: "manasMLX",
        populationSize: 2,
        generationCount: 1,
        eliteCount: 1,
        workerCount: 1,
        candidateEvaluationConcurrency: 2,
        searchStrategy: .qualityDiversity,
        bootstrapSource: .teacher,
        commonRandomSeed: 1,
        mutationRate: 0.08,
        mutationNoiseScale: 0.01,
        startedAt: startedAt,
        completedAt: completedAt,
        terminalState: .completed
    )
    let candidates = [
        GenomeCandidate(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-0",
            genomeID: "genome-0",
            checkpointID: "checkpoint-0",
            checkpointURL: checkpointRoot,
            mutationRate: 0,
            mutationNoiseScale: 0,
            commonRandomSeed: 1,
            mutationSummary: "incumbent-parent",
            isIncumbent: true
        ),
        GenomeCandidate(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-1",
            genomeID: "genome-1",
            parentCandidateIDs: ["candidate-0"],
            checkpointID: "checkpoint-1",
            checkpointURL: checkpointRoot,
            mutationRate: 0.08,
            mutationNoiseScale: 0.01,
            commonRandomSeed: 1,
            mutationSummary: "seeded"
        ),
    ]
    let fitness = [
        FitnessSummary(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-0",
            taskID: "lift",
            scalarFitness: 1,
            rewardAverage: 1,
            taskPassRate: 1,
            safetyViolationRate: 0,
            holdTimeRatio: 1,
            altitudeErrorRatio: 0,
            workerThroughput: 1,
            behaviorDescriptor: ["rank": 0]
        ),
        FitnessSummary(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-1",
            taskID: "lift",
            scalarFitness: 2,
            rewardAverage: 2,
            taskPassRate: 1,
            safetyViolationRate: 0,
            holdTimeRatio: 1,
            altitudeErrorRatio: 0,
            workerThroughput: 1,
            behaviorDescriptor: ["rank": 1]
        ),
    ]
    let generation = PopulationGenerationRecord(
        runID: runID,
        generationIndex: 0,
        candidateCount: 2,
        evaluatedCandidateCount: 2,
        eliteCandidateIDs: ["candidate-1"],
        bestCandidateID: "candidate-1",
        bestFitness: 2,
        incumbentCandidateID: "candidate-0",
        incumbentFitness: 1,
        bestVsIncumbentDelta: 1,
        qualityDiversityCellCount: 1,
        mutationRate: 0.08,
        mutationNoiseScale: 0.01,
        accepted: true,
        rejectionReasons: [],
        createdAt: completedAt
    )
    let eliteArchive = EvolutionEliteArchive(
        runID: runID,
        eliteCandidateIDs: ["candidate-1"],
        bestCandidateID: "candidate-1",
        bestFitness: 2
    )
    let qualityDiversityArchive = EvolutionQualityDiversityArchive(
        runID: runID,
        descriptorKeys: ["rank"],
        cells: [
            EvolutionQualityDiversityCell(
                cellID: "rank-1",
                candidateID: "candidate-1",
                generationIndex: 0,
                fitness: 2,
                behaviorDescriptor: ["rank": 1]
            )
        ]
    )
    let lineage = [
        EvolutionLineageRecord(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-0",
            genomeID: "genome-0",
            parentCandidateIDs: []
        ),
        EvolutionLineageRecord(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-1",
            genomeID: "genome-1",
            parentCandidateIDs: ["candidate-0"]
        ),
    ]
    let traces = [
        EvolutionCandidateEvaluationTrace(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-0",
            requestedConcurrency: 2,
            activeEvaluationCountAtStart: 1,
            startedAt: startedAt,
            completedAt: completedAt
        ),
        EvolutionCandidateEvaluationTrace(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-1",
            requestedConcurrency: 2,
            activeEvaluationCountAtStart: 2,
            startedAt: startedAt,
            completedAt: completedAt
        ),
    ]
    try EvolutionArtifactWriter().write(
        manifest: manifest,
        generations: [generation],
        candidates: candidates,
        fitness: fitness,
        eliteArchive: eliteArchive,
        qualityDiversityArchive: qualityDiversityArchive,
        lineage: lineage,
        evaluationTraces: traces,
        to: evolutionRoot
    )
}

private func rewriteSummaryFinalCheckpoint(root: URL, finalCheckpoint: String) throws {
    let url = root.appendingPathComponent("learning-campaign-summary.json")
    let data = try Data(contentsOf: url)
    let summary = try JSONDecoder().decode(LearningCampaignSummary.self, from: data)
    let replacement = LearningCampaignSummary(
        artifactRoot: summary.artifactRoot,
        seedCount: summary.seedCount,
        acceptedCount: summary.acceptedCount,
        finalCheckpoint: finalCheckpoint,
        runs: summary.runs
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(replacement).write(to: url, options: .atomic)
}

private func write(_ string: String, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(string.utf8).write(to: url, options: .atomic)
}
