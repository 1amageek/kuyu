import Foundation
import KuyuMLXTrainingProbe
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

    func validatedProbeArtifacts(in artifactDirectory: URL) throws -> TrainingProbeArtifactBundle {
        try verifier.validatedProbeArtifacts(in: artifactDirectory)
    }

    func validatedManasMLXProbeAcceptance(
        in artifactDirectory: URL
    ) throws -> ManasMLXTrainingProbeAcceptanceReceipt {
        try ManasMLXProbeAcceptanceValidator().validatedAcceptance(
            in: artifactDirectory
        )
    }

    func validatedEvolutionPublication(in artifactDirectory: URL) throws -> KuyuCLIEvolutionArtifactSnapshot {
        let artifacts = try verifier.validatedEvolutionArtifacts(in: artifactDirectory)
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
