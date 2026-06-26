import Foundation
import KuyuTraining

public protocol KuyuUITrainingArtifactReading: Sendable {
    func loadRunArtifacts(from artifactDirectory: URL) throws -> TrainingRunArtifactBundle
    func loadEvolutionArtifacts(from artifactDirectory: URL) throws -> EvolutionRunArtifactBundle
}

public struct KuyuUITrainingArtifactReader: KuyuUITrainingArtifactReading {
    private let verifier: GeneratedTrainingArtifactCompatibilityVerifier

    public init(
        verifier: GeneratedTrainingArtifactCompatibilityVerifier = GeneratedTrainingArtifactCompatibilityVerifier()
    ) {
        self.verifier = verifier
    }

    public func loadRunArtifacts(from artifactDirectory: URL) throws -> TrainingRunArtifactBundle {
        try verifier.loadRunArtifacts(from: artifactDirectory)
    }

    public func loadEvolutionArtifacts(from artifactDirectory: URL) throws -> EvolutionRunArtifactBundle {
        try verifier.loadEvolutionArtifacts(from: artifactDirectory)
    }
}
