import Foundation
import KuyuTraining
import Testing
@testable import KuyuMLX

@MainActor
@Test func learningCampaignRunConfigUsesCanonicalDefaults() throws {
    let config = LearningCampaignRunConfig(
        sourceCheckpoint: URL(fileURLWithPath: "/tmp/source", isDirectory: true),
        artifactRoot: URL(fileURLWithPath: "/tmp/artifacts", isDirectory: true)
    )

    #expect(config.task == .lift)
    #expect(config.suites == [6])
    #expect(config.seedCount == 1)
    #expect(config.population == 4)
    #expect(config.generations == 1)
    #expect(config.eliteCount == 1)
    #expect(config.workers == 1)
    #expect(config.candidateEvaluationConcurrency == 1)
    #expect(config.episodes == 1)
    #expect(config.tier == .tier1)
    #expect(config.cutPeriodSteps == 2)
    #expect(config.mutationRate == 0.08)
    #expect(config.mutationNoiseScale == 0.01)
    #expect(config.adaptiveMutationEnabled == false)
    #expect(config.minimumIncumbentImprovement == 0)
    #expect(config.artifactRetention == .full)
    #expect(config.searchStrategy == .qualityDiversity)
    #expect(config.variation == .gaussian)
    #expect(config.qualityGateEnabled == true)
}

@MainActor
@Test func learningCampaignRunnerRejectsNonEmptyArtifactRootBeforePlanWrite() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-runner-non-empty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("stale".utf8).write(to: root.appendingPathComponent("stale.txt"))

    let config = LearningCampaignRunConfig(
        sourceCheckpoint: URL(fileURLWithPath: "/tmp/source", isDirectory: true),
        artifactRoot: root
    )

    do {
        _ = try LearningCampaignRunner().makeOrchestratorConfig(config: config)
        Issue.record("Expected non-empty artifact root to be rejected.")
    } catch LearningCampaignRunError.artifactRootNotEmpty(let path) {
        #expect(path == root.path)
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("learning-campaign-plan.json").path
        ))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@MainActor
@Test func learningCampaignRunnerValidatesSeedContract() throws {
    let runner = LearningCampaignRunner()

    #expect(try runner.resolveSeeds(explicitSeeds: nil, seedCount: 3) == ["1", "2", "3"])

    do {
        _ = try runner.resolveSeeds(explicitSeeds: ["1", "1"], seedCount: 1)
        Issue.record("Expected duplicate seed to be rejected.")
    } catch LearningCampaignRunError.duplicateSeed(let seed) {
        #expect(seed == "1")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    do {
        _ = try runner.resolveSeeds(explicitSeeds: ["abc"], seedCount: 1)
        Issue.record("Expected invalid seed to be rejected.")
    } catch LearningCampaignRunError.invalidSeed(let seed) {
        #expect(seed == "abc")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@MainActor
@Test func learningCampaignHandleCancelsTaskFromProgress() async throws {
    let handle = LearningCampaignRunHandle(progress: Progress(totalUnitCount: 1))
    handle.start {
        try await Task.sleep(for: .seconds(30))
        return LearningCampaignSummary(
            artifactRoot: "/tmp/unreachable",
            seedCount: 1,
            acceptedCount: 0,
            finalCheckpoint: "/tmp/unreachable",
            runs: []
        )
    }

    handle.progress.cancel()

    do {
        _ = try await handle.wait()
        Issue.record("Expected progress cancellation to cancel the underlying task.")
    } catch is CancellationError {
        #expect(handle.progress.isCancelled)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@MainActor
@Test func learningCampaignHandleRetainsResultAfterEventStreamFinishes() async throws {
    let handle = LearningCampaignRunHandle(progress: Progress(totalUnitCount: 1))
    handle.start {
        LearningCampaignSummary(
            artifactRoot: "/tmp/kuyu-finished",
            seedCount: 1,
            acceptedCount: 1,
            finalCheckpoint: "/tmp/kuyu-finished/checkpoint",
            runs: []
        )
    }

    for await _ in handle.events {}

    let summary = try await handle.wait()
    #expect(summary.artifactRoot == "/tmp/kuyu-finished")
    #expect(summary.acceptedCount == 1)
}
