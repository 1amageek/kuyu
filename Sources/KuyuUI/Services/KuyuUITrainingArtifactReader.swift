import Foundation
import KuyuMLX
import KuyuMLXEvolution
import KuyuTraining

public protocol KuyuUITrainingArtifactReading: Sendable {
    func validatedEvolutionArtifacts(
        in artifactDirectory: URL,
        reading artifacts: any LearningCampaignArtifactReading
    ) throws -> EvolutionRunArtifactBundle

    func validatedVectorizedBatches(
        in artifactDirectory: URL,
        reading artifacts: any LearningCampaignArtifactReading
    ) throws -> [LearningCampaignVectorizedBatchState]
}

public struct KuyuUITrainingArtifactReader: KuyuUITrainingArtifactReading {
    private let verifier: GeneratedTrainingArtifactCompatibilityVerifier

    public init(
        verifier: GeneratedTrainingArtifactCompatibilityVerifier = GeneratedTrainingArtifactCompatibilityVerifier()
    ) {
        self.verifier = verifier
    }

    public func validatedEvolutionArtifacts(
        in artifactDirectory: URL,
        reading artifacts: any LearningCampaignArtifactReading
    ) throws -> EvolutionRunArtifactBundle {
        let relativeDirectory = try relativePath(
            artifactDirectory,
            artifactRoot: artifacts.artifactRoot
        )
        _ = try artifacts.regularFilePaths(
            recursivelyFrom: relativeDirectory,
            maximumFileCount: LearningCampaignArtifactReadLimits.current.maximumSnapshotFileCount
        )
        return try verifier.validatedEvolutionArtifacts(in: artifactDirectory)
    }

    public func validatedVectorizedBatches(
        in artifactDirectory: URL,
        reading artifacts: any LearningCampaignArtifactReading
    ) throws -> [LearningCampaignVectorizedBatchState] {
        guard let paths = try artifacts.regularFilePaths(
            recursivelyFrom: "",
            maximumFileCount: LearningCampaignArtifactReadLimits.current.maximumSnapshotFileCount
        ) else {
            return []
        }

        var states: [LearningCampaignVectorizedBatchState] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for relativePath in paths {
            let url = artifactDirectory.appendingPathComponent(relativePath)
            let parentName = url.deletingLastPathComponent().lastPathComponent
            switch parentName {
            case "vectorized-evaluations":
                guard let data = try artifacts.data(
                    at: relativePath,
                    maximumByteCount: LearningCampaignArtifactReadLimits.current.maximumJSONByteCount
                ) else {
                    throw LearningCampaignArtifactReadError.fileChanged(relativePath)
                }
                let artifact = try decoder.decode(
                    ManasMLXVectorizedEvaluationArtifact.self,
                    from: data
                )
                try ManasMLXVectorizedEvaluationArtifactValidator().validate(artifact)
                states.append(LearningCampaignVectorizedBatchState(
                    kind: .evaluation,
                    seed: seedLabel(for: url, artifactRoot: artifactDirectory),
                    generationIndex: artifact.generationIndex,
                    candidateCount: artifact.requestedCandidateCount,
                    completedCandidateCount: artifact.evaluatedCandidateCount,
                    elapsedSeconds: artifact.elapsedSeconds,
                    acceleratorDevice: artifact.acceleratorDevice,
                    policyExecutionMode: artifact.policyExecutionMode,
                    observationExecutionMode: artifact.observationExecutionMode,
                    worldExecutionMode: artifact.worldExecutionMode,
                    actionEncoding: artifact.batchSpec.actionEncoding.rawValue,
                    worldActiveActionDimension: artifact.worldActiveActionDimension,
                    artifactPath: url.path,
                    bestFitness: artifact.summaries.map(\.fitness).max()
                ))
            case "vectorized-variations":
                guard let data = try artifacts.data(
                    at: relativePath,
                    maximumByteCount: LearningCampaignArtifactReadLimits.current.maximumJSONByteCount
                ) else {
                    throw LearningCampaignArtifactReadError.fileChanged(relativePath)
                }
                let artifact = try decoder.decode(
                    ManasMLXVectorizedGenomeVariationArtifact.self,
                    from: data
                )
                try ManasMLXVectorizedGenomeVariationArtifactValidator().validate(artifact)
                states.append(LearningCampaignVectorizedBatchState(
                    kind: .variation,
                    seed: seedLabel(for: url, artifactRoot: artifactDirectory),
                    generationIndex: artifact.generationIndex,
                    candidateCount: artifact.requestedCandidateCount,
                    completedCandidateCount: artifact.materializedCandidateCount,
                    elapsedSeconds: artifact.elapsedSeconds,
                    acceleratorDevice: artifact.acceleratorDevice,
                    policyExecutionMode: nil,
                    observationExecutionMode: nil,
                    worldExecutionMode: nil,
                    actionEncoding: nil,
                    worldActiveActionDimension: nil,
                    artifactPath: url.path,
                    bestFitness: nil
                ))
            default:
                continue
            }
        }

        return states.sorted { lhs, rhs in
            if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
            if lhs.generationIndex != rhs.generationIndex { return lhs.generationIndex < rhs.generationIndex }
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.artifactPath < rhs.artifactPath
        }
    }

    private func relativePath(_ url: URL, artifactRoot: URL) throws -> String {
        let rootPath = artifactRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else {
            throw LearningCampaignArtifactReadError.invalidRelativePath(path)
        }
        return path == rootPath ? "" : String(path.dropFirst(rootPath.count + 1))
    }

    private func seedLabel(for url: URL, artifactRoot: URL) -> String {
        let relativePath = url.path.replacingOccurrences(of: artifactRoot.path, with: "")
        let components = relativePath.split(separator: "/").map(String.init)
        if let seedsIndex = components.firstIndex(of: "seeds"),
           components.indices.contains(seedsIndex + 1) {
            return components[seedsIndex + 1]
        }
        return "evolution"
    }
}
