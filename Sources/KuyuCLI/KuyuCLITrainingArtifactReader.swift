import Foundation
import KuyuTraining

struct KuyuCLIEvolutionArtifactSnapshot: Sendable {
    let artifacts: EvolutionRunArtifactBundle
    let publication: EvolutionArtifactPublicationProjection
}

enum KuyuCLITrainingArtifactReaderError: Error, Equatable {
    case evolutionCheckpointNotAccepted([String])
}

struct KuyuCLITrainingArtifactReader: Sendable {
    private let verifier: GeneratedTrainingArtifactCompatibilityVerifier

    init(verifier: GeneratedTrainingArtifactCompatibilityVerifier = GeneratedTrainingArtifactCompatibilityVerifier()) {
        self.verifier = verifier
    }

    func loadProbeArtifacts(from artifactDirectory: URL) throws -> TrainingProbeArtifactBundle {
        try verifier.loadProbeArtifacts(from: artifactDirectory)
    }

    func loadEvolutionPublication(from artifactDirectory: URL) throws -> KuyuCLIEvolutionArtifactSnapshot {
        let artifacts = try verifier.loadEvolutionArtifacts(from: artifactDirectory)
        return KuyuCLIEvolutionArtifactSnapshot(
            artifacts: artifacts,
            publication: verifier.evolutionPublicationProjection(for: artifacts)
        )
    }

    func requireAcceptedEvolutionCheckpoint(_ publication: EvolutionArtifactPublicationProjection) throws {
        do {
            try verifier.requireAcceptedEvolutionCheckpoint(publication)
        } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError.evolutionCheckpointNotAccepted(let reasons) {
            throw KuyuCLITrainingArtifactReaderError.evolutionCheckpointNotAccepted(reasons)
        }
    }
}
