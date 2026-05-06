import Foundation
import KuyuMLX
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
      "acceptedCount": 0,
      "artifactRoot": "\(root.path)",
      "finalCheckpoint": "\(checkpointRoot.path)",
      "runs": [
        {
          "accepted": false,
          "acceptedCandidateID": null,
          "acceptedCheckpointURL": null,
          "bestCandidateID": "candidate-1",
          "bestFitness": 1.0,
          "bestHoldTimeRatio": 1.0,
          "bestRewardAverage": 1.0,
          "bestSafetyViolationRate": 0.0,
          "bestTaskPassRate": 1.0,
          "bestVsIncumbentDelta": 0.0,
          "evaluationTraceCount": 2,
          "fitnessCount": 2,
          "incumbentCandidateID": "candidate-0",
          "incumbentFitness": 1.0,
          "overlappedEvaluation": true,
          "reasonCount": 1,
          "seed": "1",
          "terminalState": "completed"
        }
      ],
      "seedCount": 1
    }
    """, to: root.appendingPathComponent("learning-campaign-summary.json"))

    for fileName in [
        "accepted-checkpoint.json",
        "evolution-manifest.json",
        "evaluation-trace.jsonl",
        "fitness.jsonl",
        "candidates.jsonl"
    ] {
        try write("{}", to: evolutionRoot.appendingPathComponent(fileName))
    }
    try write("{}", to: checkpointRoot.appendingPathComponent("model.json"))
    try write("core", to: checkpointRoot.appendingPathComponent("core.safetensors"))
    try write("reflex", to: checkpointRoot.appendingPathComponent("reflex.safetensors"))
    return root
}

private func write(_ string: String, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(string.utf8).write(to: url, options: .atomic)
}
