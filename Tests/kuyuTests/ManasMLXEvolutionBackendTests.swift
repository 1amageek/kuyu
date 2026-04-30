import Foundation
import KuyuTraining
import Testing
@testable import KuyuMLX

@MainActor
@Test func manasMLXEvolutionBackendProducesFileBackedPopulationAndLineage() async throws {
    let directory = try evolutionBackendTemporaryDirectory()
    defer { evolutionBackendCleanup(directory) }
    let sourceCheckpoint = directory.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceCheckpoint, withIntermediateDirectories: true)
    try Data("checkpoint".utf8).write(to: sourceCheckpoint.appendingPathComponent("model.json"))

    let backend = ManasMLXEvolutionBackend(
        rootDirectory: directory.appendingPathComponent("evolution", isDirectory: true),
        variationProvider: ManasMLXFileBackedGenomeVariationProvider()
    )
    let config = EvolutionRunConfig(
        runID: "mlx-evolution",
        taskID: "lift",
        configHash: "config-hash",
        policyID: "manasMLX",
        populationSize: 3,
        generationCount: 2,
        eliteCount: 1,
        workerCount: 2,
        searchStrategy: .antitheticEvolutionStrategy,
        commonRandomSeed: 77,
        mutationRate: 0.08,
        mutationNoiseScale: 0.03,
        parentCheckpointID: "source",
        parentCheckpointURL: sourceCheckpoint
    )

    let seed = try await backend.seedPopulation(request: EvolutionSeedRequest(
        config: config,
        artifactDirectory: directory,
        mutationRate: 0.12,
        mutationNoiseScale: 0.02,
        commonRandomSeed: 101
    ))
    let next = try await backend.produceNextGeneration(request: EvolutionGenerationRequest(
        config: config,
        previousPopulation: seed,
        fitness: [
            FitnessSummary(
                runID: config.runID,
                generationIndex: 0,
                candidateID: "g0-c2",
                taskID: "lift",
                scalarFitness: 2,
                rewardAverage: 2,
                taskPassRate: 1,
                safetyViolationRate: 0
            )
        ],
        eliteCandidateIDs: ["g0-c2"],
        generationArtifactDirectory: directory.appendingPathComponent("generation-0", isDirectory: true)
    ))

    #expect(seed.candidates.count == 3)
    #expect(next.candidates.count == 3)
    #expect(seed.candidates.first?.parentCandidateIDs == [])
    #expect(next.candidates.first?.parentCandidateIDs == ["g0-c2"])
    #expect(seed.candidates[0].antitheticPairID == "g0-p0")
    #expect(seed.candidates[1].antitheticPairID == "g0-p0")
    #expect(seed.candidates[0].antitheticSign == 1)
    #expect(seed.candidates[1].antitheticSign == -1)
    #expect(seed.candidates[0].mutationRate == 0)
    #expect(seed.candidates[0].mutationNoiseScale == 0)
    #expect(seed.candidates[0].isIncumbent == true)
    #expect(seed.candidates[0].mutationSummary == "incumbent-parent")
    #expect(seed.candidates[1].mutationRate == 0.12)
    #expect(seed.candidates[1].mutationNoiseScale == 0.02)
    #expect(seed.candidates[1].isIncumbent != true)
    #expect(seed.candidates[0].commonRandomSeed == 101)
    #expect(next.candidates[0].antitheticPairID == "g1-p0")
    #expect(next.candidates[1].antitheticSign == -1)
    #expect(FileManager.default.fileExists(atPath: seed.candidates.first?.checkpointURL?.appendingPathComponent("model.json").path ?? ""))
    #expect(FileManager.default.fileExists(atPath: next.candidates.first?.checkpointURL?.appendingPathComponent("genome-candidate.json").path ?? ""))

    let descriptorURL = try #require(seed.candidates.first?.checkpointURL?.appendingPathComponent("genome-candidate.json"))
    let descriptorData = try Data(contentsOf: descriptorURL)
    let descriptor = try JSONDecoder().decode(ManasMLXGenomeCandidateDescriptor.self, from: descriptorData)
    #expect(descriptor.antitheticPairID == "g0-p0")
    #expect(descriptor.antitheticSign == 1)
    #expect(descriptor.mutationRate == 0)
    #expect(descriptor.mutationNoiseScale == 0)
    #expect(descriptor.isIncumbent)
    #expect(descriptor.commonRandomSeed == 101)
}

@MainActor
@Test(
    .enabled(if: mlxSaveLoadSmokeEnabled),
    .timeLimit(.minutes(1))
)
func manasMLXGaussianMutationProducesReloadableCheckpoint() async throws {
    let directory = try evolutionBackendTemporaryDirectory()
    defer { evolutionBackendCleanup(directory) }
    let sourceCheckpoint = directory.appendingPathComponent("source", isDirectory: true)
    let candidateRoot = directory.appendingPathComponent("evolution", isDirectory: true)

    let sourceStore = ManasMLXModelStore()
    sourceStore.initializeModelsForTesting(
        inputSize: 16,
        driveCount: 4,
        auxEnabled: true,
        reflexInputSize: 6
    )
    let sourceManifest = try sourceStore.saveModel(to: sourceCheckpoint, name: "gaussian-source")

    let provider = ManasMLXGaussianMutationProvider(config: ManasMLXGaussianMutationConfig(
        noiseScale: 0.01,
        crossoverEnabled: true
    ))
    let backend = ManasMLXEvolutionBackend(
        rootDirectory: candidateRoot,
        variationProvider: provider
    )
    let config = EvolutionRunConfig(
        runID: "mlx-gaussian-evolution",
        taskID: "lift",
        configHash: "config-hash",
        policyID: "manasMLX",
        populationSize: 2,
        generationCount: 1,
        eliteCount: 1,
        workerCount: 1,
        mutationRate: 0.1,
        parentCheckpointID: "source",
        parentCheckpointURL: sourceCheckpoint
    )

    let seed = try await backend.seedPopulation(request: EvolutionSeedRequest(
        config: config,
        artifactDirectory: directory
    ))

    #expect(seed.candidates.count == 2)
    for candidate in seed.candidates {
        let checkpointURL = try #require(candidate.checkpointURL)
        #expect(FileManager.default.fileExists(atPath: checkpointURL.appendingPathComponent("model.json").path))
        #expect(FileManager.default.fileExists(atPath: checkpointURL.appendingPathComponent("core.safetensors").path))
        #expect(FileManager.default.fileExists(atPath: checkpointURL.appendingPathComponent("reflex.safetensors").path))
        #expect(FileManager.default.fileExists(atPath: checkpointURL.appendingPathComponent("genome-candidate.json").path))

        let candidateStore = ManasMLXModelStore()
        let candidateManifest = try candidateStore.loadModel(from: checkpointURL)
        #expect(candidateManifest.coreConfig == sourceManifest.coreConfig)
        #expect(candidateManifest.reflexConfig == sourceManifest.reflexConfig)
    }
}

private func evolutionBackendTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-mlx-evolution-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func evolutionBackendCleanup(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove \(url.path): \(error)")
    }
}

#if Xcode
private let mlxSaveLoadSmokeEnabled = true
#else
private let mlxSaveLoadSmokeEnabled = false
#endif
