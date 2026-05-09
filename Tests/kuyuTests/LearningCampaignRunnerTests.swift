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
    #expect(config.requiresInitialParentPass == true)
    #expect(config.autonomyDomain == .aerialDrone)
    #expect(config.autonomousPipelinePlan == nil)
}

@MainActor
@Test func learningCampaignRunnerCanPlanStarterSearchWithoutInitialParentPassGate() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-runner-starter-parent-gate-\(UUID().uuidString)", isDirectory: true)
    let config = LearningCampaignRunConfig(
        sourceCheckpoint: URL(fileURLWithPath: "/tmp/source", isDirectory: true),
        artifactRoot: root,
        requiresInitialParentPass: false
    )

    let orchestratorConfig = try LearningCampaignRunner().makeOrchestratorConfig(config: config)

    #expect(orchestratorConfig.plan.verifyParentTask == false)
}

@MainActor
@Test func learningCampaignFiveGenerationPresetUsesMachineOptimizedParallelism() throws {
    let base = LearningCampaignRunConfig(
        sourceCheckpoint: URL(fileURLWithPath: "/tmp/source", isDirectory: true),
        artifactRoot: URL(fileURLWithPath: "/tmp/artifacts", isDirectory: true)
    )
    let capacity = LearningCampaignMachineCapacity(
        activeProcessorCount: 14,
        physicalMemoryBytes: 36 * 1_024 * 1_024 * 1_024
    )
    let config = LearningCampaignRunPreset
        .fiveGeneration
        .apply(to: base)
        .optimizedForMachine(capacity)

    #expect(config.population == 8)
    #expect(config.generations == 5)
    #expect(config.eliteCount == 2)
    #expect(config.workers == 1)
    #expect(config.candidateEvaluationConcurrency == 8)
    #expect(capacity.recommendation(
        population: config.population,
        suiteCount: config.suites.count,
        episodes: config.episodes
    ).totalParallelSlots == 8)
}

@MainActor
@Test func learningCampaignRunnerEmbedsValidatedAutonomyPipelineInPlan() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-runner-autonomy-plan-\(UUID().uuidString)", isDirectory: true)
    let config = LearningCampaignRunConfig(
        sourceCheckpoint: URL(fileURLWithPath: "/tmp/source", isDirectory: true),
        artifactRoot: root
    )

    let orchestratorConfig = try LearningCampaignRunner().makeOrchestratorConfig(config: config)
    let pipeline = try #require(orchestratorConfig.plan.autonomousPipeline)

    #expect(pipeline.domain == .aerialDrone)
    #expect(pipeline.stages.contains { $0.kind == .imitation })
    #expect(pipeline.stages.contains { $0.kind == .evolution })
    #expect(pipeline.stages.contains { $0.kind == .hardwareInTheLoop })
    #expect(pipeline.terminalGates.contains(.modelBundleValidated))
    #expect(pipeline.terminalGates.contains(.hardwareBoundaryValidated))
}

@MainActor
@Test func learningCampaignRunnerRejectsMismatchedAutonomyPipelineDomain() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-runner-autonomy-domain-\(UUID().uuidString)", isDirectory: true)
    let pipeline = AutonomousTrainingPipelineFactory().defaultPlan(
        domain: .automotive,
        taskProfileIDs: ["lift-v1"]
    )
    let config = LearningCampaignRunConfig(
        sourceCheckpoint: URL(fileURLWithPath: "/tmp/source", isDirectory: true),
        artifactRoot: root,
        autonomyDomain: .aerialDrone,
        autonomousPipelinePlan: pipeline
    )

    do {
        _ = try LearningCampaignRunner().makeOrchestratorConfig(config: config)
        Issue.record("Expected mismatched autonomy domain to be rejected.")
    } catch LearningCampaignRunError.invalidConfig(let message) {
        #expect(message.contains("does not match config domain"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@MainActor
@Test func learningCampaignRunnerCarriesReinforcementArtifactDirectoryIntoPlan() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-runner-rl-artifact-\(UUID().uuidString)", isDirectory: true)
    let reinforcementArtifact = root
        .deletingLastPathComponent()
        .appendingPathComponent("rl-training-run", isDirectory: true)
    let config = LearningCampaignRunConfig(
        sourceCheckpoint: URL(fileURLWithPath: "/tmp/source", isDirectory: true),
        artifactRoot: root,
        reinforcementTrainingArtifactDirectory: reinforcementArtifact
    )

    let orchestratorConfig = try LearningCampaignRunner().makeOrchestratorConfig(config: config)

    #expect(orchestratorConfig.plan.reinforcementTrainingArtifactDirectory == reinforcementArtifact.path)
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
