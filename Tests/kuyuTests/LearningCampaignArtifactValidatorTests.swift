import Foundation
import KuyuMLX
import KuyuTraining
import Testing

@Test func learningCampaignArtifactValidatorAcceptsCompleteCampaign() throws {
    let root = try makeLearningCampaignArtifactRoot()

    let validation = try LearningCampaignArtifactValidator().validate(artifactRoot: root)

    #expect(validation.valid)
    #expect(validation.issueCount == 0)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("learning-campaign-validation.json").path))
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
          "bestHoldTimeRatio": 1.0,
          "bestRewardAverage": 2.0,
          "bestSafetyViolationRate": 0.0,
          "bestTaskPassRate": 1.0,
          "bestVsIncumbentDelta": 1.0,
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
    try writeValidEvolutionArtifacts(evolutionRoot: evolutionRoot, checkpointRoot: checkpointRoot)
    return root
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

private func write(_ string: String, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(string.utf8).write(to: url, options: .atomic)
}
