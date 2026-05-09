import Foundation
import KuyuMLX
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
    try writeJSON(
        LearningCampaignValidation(
            timestamp: "2026-05-07T00:00:01Z",
            artifactRoot: root.path,
            valid: true,
            issueCount: 0,
            issues: []
        ),
        to: root.appendingPathComponent("learning-campaign-validation.json")
    )
    try writeLine(
        LearningCampaignProgressRecord(
            event: "seed-started",
            timestamp: "2026-05-07T00:00:02Z",
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
    #expect(state.validationLabel == "valid")
    #expect(state.progressEvents.count == 1)
    #expect(state.generations.count == 1)
    #expect(state.bestDelta == 2)
    #expect(state.latestGenerations.first?.incumbentImproved == true)
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
    try """
    {
      "artifactRoot": "\(root.path)",
      "issueCount": 1,
      "issues": [
        {
          "code": "accepted-checkpoint-missing",
          "detail": "accepted checkpoint artifact is missing"
        }
      ],
      "timestamp": "2026-05-07T00:01:01Z",
      "valid": false
    }
    """.write(
        to: root.appendingPathComponent("learning-campaign-validation.json"),
        atomically: true,
        encoding: .utf8
    )
    try writeLine(
        LearningCampaignProgressRecord(
            event: "validation-failed",
            timestamp: "2026-05-07T00:01:02Z",
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

    #expect(state.primaryFailureReason == "validation:accepted-checkpoint-missing: accepted checkpoint artifact is missing")
    #expect(state.failureReasons.contains("generation:seed-1:g0: minimum-incumbent-improvement"))
    #expect(state.failureReasons.contains("status: failed"))
    #expect(state.failureReasons.contains("event:2026-05-07T00:01:02Z: validation-failed"))
    #expect(state.failureReasons.contains("exitCode: 1"))
    #expect(state.diagnosticText.contains("failureReasons:"))
    #expect(state.diagnosticText.contains("accepted-checkpoint-missing"))
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
    #expect(state.plan?.population == 8)
    #expect(state.plan?.generations == 5)
    #expect(state.plan?.candidateEvaluationConcurrency == 8)
    #expect(state.generations.count == 5)
    #expect(state.candidates.count == 5)
    #expect(state.maxRequestedCandidateConcurrency == 8)
    #expect(state.maxActiveCandidateEvaluations == 8)
    #expect(state.candidateEvaluationCount == 5)
    #expect(state.actualParallelismLabel == "8/8 active")
    #expect(state.averageCandidateEvaluationDurationSeconds == 1)
    #expect(state.candidates(seed: "evolution", generationIndex: 4).first?.parentCandidateIDs == ["g3-c7", "g3-c6"])
    #expect(state.latestGenerations.first?.seed == "evolution")
    #expect(state.latestGenerations.first?.generationIndex == 4)
}

private func makePlan(root: URL) -> LearningCampaignPlan {
    LearningCampaignPlan(
        artifactRoot: root.path,
        task: "singleLift",
        suites: ["6", "7"],
        episodes: 1,
        workers: 2,
        population: 4,
        generations: 2,
        eliteCount: 1,
        candidateEvaluationConcurrency: 2,
        seeds: ["seed-1"],
        sourceCheckpoint: nil,
        modelDescriptor: nil,
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
        suites: ["6"],
        episodes: 1,
        workers: 1,
        population: 8,
        generations: 5,
        eliteCount: 2,
        candidateEvaluationConcurrency: 8,
        seeds: ["seed-1"],
        sourceCheckpoint: nil,
        modelDescriptor: nil,
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
