import Foundation
import KuyuTraining
import MLX
import MLXRandom

public struct ManasMLXGenomeCandidateDescriptor: Sendable, Codable, Equatable {
    public let candidateID: String
    public let genomeID: String
    public let generationIndex: Int
    public let parentCandidateIDs: [String]
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let commonRandomSeed: UInt64
    public let antitheticPairID: String?
    public let antitheticSign: Int?
    public let sourceCheckpointURL: URL?
    public let parentCheckpointURLs: [URL]

    public init(
        candidateID: String,
        genomeID: String,
        generationIndex: Int,
        parentCandidateIDs: [String],
        mutationRate: Double,
        mutationNoiseScale: Double,
        commonRandomSeed: UInt64,
        antitheticPairID: String?,
        antitheticSign: Int?,
        sourceCheckpointURL: URL?,
        parentCheckpointURLs: [URL] = []
    ) {
        self.candidateID = candidateID
        self.genomeID = genomeID
        self.generationIndex = max(0, generationIndex)
        self.parentCandidateIDs = parentCandidateIDs
        self.mutationRate = mutationRate
        self.mutationNoiseScale = max(0, mutationNoiseScale)
        self.commonRandomSeed = commonRandomSeed
        self.antitheticPairID = antitheticPairID
        self.antitheticSign = antitheticSign
        self.sourceCheckpointURL = sourceCheckpointURL
        self.parentCheckpointURLs = parentCheckpointURLs
    }
}

public struct ManasMLXGenomeVariationRequest: Sendable, Equatable {
    public let config: EvolutionRunConfig
    public let generationIndex: Int
    public let candidateIndex: Int
    public let parentCandidateIDs: [String]
    public let sourceCheckpointURL: URL?
    public let parentCheckpointURLs: [URL]
    public let candidateDirectory: URL
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let commonRandomSeed: UInt64
    public let antitheticPairID: String?
    public let antitheticSign: Int?

    public init(
        config: EvolutionRunConfig,
        generationIndex: Int,
        candidateIndex: Int,
        parentCandidateIDs: [String],
        sourceCheckpointURL: URL?,
        parentCheckpointURLs: [URL] = [],
        candidateDirectory: URL,
        mutationRate: Double? = nil,
        mutationNoiseScale: Double? = nil,
        commonRandomSeed: UInt64? = nil,
        antitheticPairID: String? = nil,
        antitheticSign: Int? = nil
    ) {
        self.config = config
        self.generationIndex = max(0, generationIndex)
        self.candidateIndex = max(0, candidateIndex)
        self.parentCandidateIDs = parentCandidateIDs
        self.sourceCheckpointURL = sourceCheckpointURL
        self.parentCheckpointURLs = parentCheckpointURLs
        self.candidateDirectory = candidateDirectory
        self.mutationRate = mutationRate ?? config.mutationRate
        self.mutationNoiseScale = mutationNoiseScale ?? config.mutationNoiseScale
        self.commonRandomSeed = commonRandomSeed ?? config.commonRandomSeed
        self.antitheticPairID = antitheticPairID
        self.antitheticSign = antitheticSign
    }
}

@MainActor
public protocol ManasMLXGenomeVariationProviding {
    func makeCandidate(request: ManasMLXGenomeVariationRequest) async throws -> GenomeCandidate
}

@MainActor
public struct ManasMLXFileBackedGenomeVariationProvider: ManasMLXGenomeVariationProviding {
    public init() {}

    public func makeCandidate(request: ManasMLXGenomeVariationRequest) async throws -> GenomeCandidate {
        try FileManager.default.createDirectory(
            at: request.candidateDirectory,
            withIntermediateDirectories: true
        )
        if let sourceCheckpointURL = request.sourceCheckpointURL,
           FileManager.default.fileExists(atPath: sourceCheckpointURL.path) {
            try copyCheckpointContents(from: sourceCheckpointURL, to: request.candidateDirectory)
        }
        let candidateID = "g\(request.generationIndex)-c\(request.candidateIndex)"
        let genomeID = "\(request.config.runID)-\(candidateID)"
        let descriptor = ManasMLXGenomeCandidateDescriptor(
            candidateID: candidateID,
            genomeID: genomeID,
            generationIndex: request.generationIndex,
            parentCandidateIDs: request.parentCandidateIDs,
            mutationRate: request.mutationRate,
            mutationNoiseScale: request.mutationNoiseScale,
            commonRandomSeed: request.commonRandomSeed,
            antitheticPairID: request.antitheticPairID,
            antitheticSign: request.antitheticSign,
            sourceCheckpointURL: request.sourceCheckpointURL,
            parentCheckpointURLs: request.parentCheckpointURLs
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(descriptor).write(
            to: request.candidateDirectory.appendingPathComponent("genome-candidate.json"),
            options: [.atomic]
        )
        return GenomeCandidate(
            runID: request.config.runID,
            generationIndex: request.generationIndex,
            candidateID: candidateID,
            genomeID: genomeID,
            parentCandidateIDs: request.parentCandidateIDs,
            checkpointID: candidateID,
            checkpointURL: request.candidateDirectory,
            mutationRate: request.mutationRate,
            mutationNoiseScale: request.mutationNoiseScale,
            commonRandomSeed: request.commonRandomSeed,
            antitheticPairID: request.antitheticPairID,
            antitheticSign: request.antitheticSign,
            mutationSummary: request.generationIndex == 0 ? "seed" : "variation-provider"
        )
    }

    private func copyCheckpointContents(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )
        for item in contents {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: item, to: target)
        }
    }
}

public struct ManasMLXGaussianMutationConfig: Sendable, Codable, Equatable {
    public let noiseScale: Float
    public let crossoverEnabled: Bool

    public init(
        noiseScale: Float = 0.01,
        crossoverEnabled: Bool = true
    ) {
        self.noiseScale = max(0, noiseScale)
        self.crossoverEnabled = crossoverEnabled
    }
}

@MainActor
public struct ManasMLXGaussianMutationProvider: ManasMLXGenomeVariationProviding {
    public enum MutationError: Error, Sendable, Equatable {
        case missingSourceCheckpoint
        case missingRequiredWeights(String)
    }

    private let config: ManasMLXGaussianMutationConfig

    public init(config: ManasMLXGaussianMutationConfig = ManasMLXGaussianMutationConfig()) {
        self.config = config
    }

    public func makeCandidate(request: ManasMLXGenomeVariationRequest) async throws -> GenomeCandidate {
        guard let sourceCheckpointURL = request.sourceCheckpointURL else {
            throw MutationError.missingSourceCheckpoint
        }
        try FileManager.default.createDirectory(
            at: request.candidateDirectory,
            withIntermediateDirectories: true
        )
        try copyStaticCheckpointFiles(from: sourceCheckpointURL, to: request.candidateDirectory)
        try writeMutatedWeights(
            fileName: "core.safetensors",
            request: request,
            sourceCheckpointURL: sourceCheckpointURL
        )
        let reflexSourceURL = sourceCheckpointURL.appendingPathComponent("reflex.safetensors")
        if FileManager.default.fileExists(atPath: reflexSourceURL.path) {
            try writeMutatedWeights(
                fileName: "reflex.safetensors",
                request: request,
                sourceCheckpointURL: sourceCheckpointURL
            )
        }
        try writeDescriptor(request: request, sourceCheckpointURL: sourceCheckpointURL)
        let candidateID = "g\(request.generationIndex)-c\(request.candidateIndex)"
        let genomeID = "\(request.config.runID)-\(candidateID)"
        return GenomeCandidate(
            runID: request.config.runID,
            generationIndex: request.generationIndex,
            candidateID: candidateID,
            genomeID: genomeID,
            parentCandidateIDs: request.parentCandidateIDs,
            checkpointID: candidateID,
            checkpointURL: request.candidateDirectory,
            mutationRate: request.mutationRate,
            mutationNoiseScale: request.mutationNoiseScale,
            commonRandomSeed: request.commonRandomSeed,
            antitheticPairID: request.antitheticPairID,
            antitheticSign: request.antitheticSign,
            mutationSummary: request.generationIndex == 0 ? "gaussian-seed-mutation" : "gaussian-crossover-mutation"
        )
    }

    private func writeMutatedWeights(
        fileName: String,
        request: ManasMLXGenomeVariationRequest,
        sourceCheckpointURL: URL
    ) throws {
        let sourceURL = sourceCheckpointURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MutationError.missingRequiredWeights(fileName)
        }
        let sourceArrays = try MLX.loadArrays(url: sourceURL)
        let parentArrays = try parentWeightArrays(
            fileName: fileName,
            request: request,
            fallback: sourceArrays
        )
        let mutated = Dictionary(
            uniqueKeysWithValues: parentArrays.sorted { $0.key < $1.key }.enumerated().map { index, entry in
                let seed = mutationSeed(
                    runID: request.config.runID,
                    generationIndex: request.generationIndex,
                    candidateIndex: request.candidateIndex,
                    parameterIndex: index,
                    fileName: fileName,
                    commonRandomSeed: request.commonRandomSeed,
                    antitheticPairID: request.antitheticPairID
                )
                let noise = MLXRandom.normal(
                    entry.value.shape,
                    dtype: entry.value.dtype,
                    loc: 0,
                    scale: config.noiseScale * Float(request.mutationNoiseScale) * Float(request.mutationRate),
                    key: MLXRandom.key(seed)
                )
                return (entry.key, entry.value + noise * Float(request.antitheticSign ?? 1))
            }
        )
        try MLX.save(
            arrays: mutated,
            url: request.candidateDirectory.appendingPathComponent(fileName)
        )
    }

    private func parentWeightArrays(
        fileName: String,
        request: ManasMLXGenomeVariationRequest,
        fallback: [String: MLXArray]
    ) throws -> [String: MLXArray] {
        guard config.crossoverEnabled,
              request.parentCheckpointURLs.count > 1 else {
            return fallback
        }
        let parentArraySets = try request.parentCheckpointURLs.compactMap { url -> [String: MLXArray]? in
            let weightURL = url.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: weightURL.path) else {
                return nil
            }
            return try MLX.loadArrays(url: weightURL)
        }
        guard parentArraySets.count > 1 else {
            return fallback
        }
        var averaged: [String: MLXArray] = [:]
        for key in fallback.keys {
            let arrays = parentArraySets.compactMap { $0[key] }
            guard arrays.count == parentArraySets.count else {
                return fallback
            }
            let sum = arrays.dropFirst().reduce(arrays[0]) { partial, array in
                partial + array
            }
            averaged[key] = sum / Float(arrays.count)
        }
        return averaged
    }

    private func copyStaticCheckpointFiles(from source: URL, to destination: URL) throws {
        let modelURL = source.appendingPathComponent("model.json")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw MutationError.missingRequiredWeights("model.json")
        }
        let targetURL = destination.appendingPathComponent("model.json")
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.copyItem(at: modelURL, to: targetURL)
    }

    private func writeDescriptor(
        request: ManasMLXGenomeVariationRequest,
        sourceCheckpointURL: URL
    ) throws {
        let candidateID = "g\(request.generationIndex)-c\(request.candidateIndex)"
        let genomeID = "\(request.config.runID)-\(candidateID)"
        let descriptor = ManasMLXGenomeCandidateDescriptor(
            candidateID: candidateID,
            genomeID: genomeID,
            generationIndex: request.generationIndex,
            parentCandidateIDs: request.parentCandidateIDs,
            mutationRate: request.mutationRate,
            mutationNoiseScale: request.mutationNoiseScale,
            commonRandomSeed: request.commonRandomSeed,
            antitheticPairID: request.antitheticPairID,
            antitheticSign: request.antitheticSign,
            sourceCheckpointURL: sourceCheckpointURL,
            parentCheckpointURLs: request.parentCheckpointURLs
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(descriptor).write(
            to: request.candidateDirectory.appendingPathComponent("genome-candidate.json"),
            options: [.atomic]
        )
    }

    private func mutationSeed(
        runID: String,
        generationIndex: Int,
        candidateIndex: Int,
        parameterIndex: Int,
        fileName: String,
        commonRandomSeed: UInt64,
        antitheticPairID: String?
    ) -> UInt64 {
        let antitheticKey = antitheticPairID ?? "candidate-\(candidateIndex)"
        let text = "\(commonRandomSeed)|\(runID)|\(generationIndex)|\(antitheticKey)|\(parameterIndex)|\(fileName)"
        return text.utf8.reduce(1_469_598_103_934_665_603) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

@MainActor
public struct ManasMLXEvolutionBackend: EvolutionaryTrainingBackend {
    public enum BackendError: Error, Sendable, Equatable {
        case emptyPreviousPopulation
    }

    private let rootDirectory: URL
    private let variationProvider: any ManasMLXGenomeVariationProviding

    public init(
        rootDirectory: URL,
        variationProvider: any ManasMLXGenomeVariationProviding = ManasMLXGaussianMutationProvider()
    ) {
        self.rootDirectory = rootDirectory
        self.variationProvider = variationProvider
    }

    public func seedPopulation(request: EvolutionSeedRequest) async throws -> EvolutionPopulation {
        try await makePopulation(
            config: request.config,
            generationIndex: 0,
            parentCandidateIDs: [],
            sourceCheckpointURL: request.config.parentCheckpointURL,
            parentCheckpointURLs: request.config.parentCheckpointURL.map { [$0] } ?? [],
            mutationRate: request.mutationRate,
            mutationNoiseScale: request.mutationNoiseScale,
            commonRandomSeed: request.commonRandomSeed
        )
    }

    public func produceNextGeneration(request: EvolutionGenerationRequest) async throws -> EvolutionPopulation {
        let parentIDs = request.eliteCandidateIDs.isEmpty
            ? try fallbackParentIDs(from: request)
            : request.eliteCandidateIDs
        return try await makePopulation(
            config: request.config,
            generationIndex: request.previousPopulation.generationIndex + 1,
            parentCandidateIDs: parentIDs,
            sourceCheckpointURL: bestParentCheckpointURL(request: request, parentIDs: parentIDs),
            parentCheckpointURLs: parentCheckpointURLs(request: request, parentIDs: parentIDs),
            mutationRate: request.mutationRate,
            mutationNoiseScale: request.mutationNoiseScale,
            commonRandomSeed: request.commonRandomSeed
        )
    }

    private func makePopulation(
        config: EvolutionRunConfig,
        generationIndex: Int,
        parentCandidateIDs: [String],
        sourceCheckpointURL: URL?,
        parentCheckpointURLs: [URL],
        mutationRate: Double,
        mutationNoiseScale: Double,
        commonRandomSeed: UInt64
    ) async throws -> EvolutionPopulation {
        var candidates: [GenomeCandidate] = []
        candidates.reserveCapacity(config.populationSize)
        for index in 0..<config.populationSize {
            let candidate = try await variationProvider.makeCandidate(request: ManasMLXGenomeVariationRequest(
                config: config,
                generationIndex: generationIndex,
                candidateIndex: index,
                parentCandidateIDs: parentCandidateIDs,
                sourceCheckpointURL: sourceCheckpointURL,
                parentCheckpointURLs: parentCheckpointURLs,
                candidateDirectory: candidateDirectory(
                    runID: config.runID,
                    generationIndex: generationIndex,
                    candidateIndex: index
                ),
                mutationRate: mutationRate,
                mutationNoiseScale: mutationNoiseScale,
                commonRandomSeed: commonRandomSeed,
                antitheticPairID: antitheticPairID(config: config, generationIndex: generationIndex, candidateIndex: index),
                antitheticSign: antitheticSign(config: config, candidateIndex: index)
            ))
            candidates.append(candidate)
        }
        return EvolutionPopulation(
            runID: config.runID,
            generationIndex: generationIndex,
            candidates: candidates
        )
    }

    private func antitheticPairID(
        config: EvolutionRunConfig,
        generationIndex: Int,
        candidateIndex: Int
    ) -> String? {
        guard config.antitheticSampling else { return nil }
        return "g\(generationIndex)-p\(candidateIndex / 2)"
    }

    private func antitheticSign(config: EvolutionRunConfig, candidateIndex: Int) -> Int? {
        guard config.antitheticSampling else { return nil }
        return candidateIndex.isMultiple(of: 2) ? 1 : -1
    }

    private func candidateDirectory(
        runID: String,
        generationIndex: Int,
        candidateIndex: Int
    ) -> URL {
        rootDirectory
            .appendingPathComponent(runID, isDirectory: true)
            .appendingPathComponent("generation-\(generationIndex)", isDirectory: true)
            .appendingPathComponent("candidate-\(candidateIndex)", isDirectory: true)
    }

    private func fallbackParentIDs(from request: EvolutionGenerationRequest) throws -> [String] {
        guard let best = request.fitness
            .filter({ $0.scalarFitness.isFinite })
            .sorted(by: { lhs, rhs in
                if lhs.scalarFitness == rhs.scalarFitness {
                    return lhs.candidateID < rhs.candidateID
                }
                return lhs.scalarFitness > rhs.scalarFitness
            })
            .first else {
            throw BackendError.emptyPreviousPopulation
        }
        return [best.candidateID]
    }

    private func bestParentCheckpointURL(
        request: EvolutionGenerationRequest,
        parentIDs: [String]
    ) -> URL? {
        request.previousPopulation.candidates
            .first { parentIDs.contains($0.candidateID) }?
            .checkpointURL
    }

    private func parentCheckpointURLs(
        request: EvolutionGenerationRequest,
        parentIDs: [String]
    ) -> [URL] {
        request.previousPopulation.candidates.compactMap { candidate in
            parentIDs.contains(candidate.candidateID) ? candidate.checkpointURL : nil
        }
    }
}
