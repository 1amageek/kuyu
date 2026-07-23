import Foundation
import KuyuMLXReferenceQuadrotor

extension RunFoundationAcceptance {
    func foundationAcceptanceCampaignSource(
        artifactRoot: URL
    ) throws -> ReferenceQuadrotorFoundationCampaignSource {
        if let completedCampaignArtifactRootPath {
            return .completedArtifact(
                artifactRoot: URL(
                    fileURLWithPath: completedCampaignArtifactRootPath,
                    isDirectory: true
                ).standardizedFileURL
            )
        }
        return .training(
            sourceCheckpointURL: try foundationAcceptanceSourceCheckpointURL(
                artifactRoot: artifactRoot
            )
        )
    }
}
