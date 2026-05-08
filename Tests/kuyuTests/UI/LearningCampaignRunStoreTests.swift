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
