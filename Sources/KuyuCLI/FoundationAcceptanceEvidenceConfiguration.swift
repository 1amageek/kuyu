import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXReferenceQuadrotor

struct FoundationAcceptanceEvidenceConfiguration: Sendable, Equatable {
    let tier: LearningCampaignTier
    let cutPeriodSteps: UInt64
    let robotManifestPath: String
    let kp: Double
    let kd: Double
    let yawDamping: Double
    let hoverScale: Double
}

extension RunFoundationAcceptance {
    func foundationAcceptanceEvidenceConfiguration(
        campaignSource: ReferenceQuadrotorFoundationCampaignSource,
        artifactRoot: URL
    ) throws -> FoundationAcceptanceEvidenceConfiguration {
        switch campaignSource {
        case .training:
            return FoundationAcceptanceEvidenceConfiguration(
                tier: tier,
                cutPeriodSteps: cutPeriodSteps,
                robotManifestPath: model,
                kp: kp,
                kd: kd,
                yawDamping: yawDamping,
                hoverScale: hoverScale
            )
        case .completedArtifact(let campaignRoot):
            let plan = try ReferenceQuadrotorFoundationCompletedCampaignLoader().load(
                artifactRoot: campaignRoot,
                foundationArtifactRoot: artifactRoot
            ).plan
            guard let robotManifestPath = plan.robotManifest,
                  !robotManifestPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError("Completed campaign is missing its robot manifest path.")
            }
            return FoundationAcceptanceEvidenceConfiguration(
                tier: plan.tier,
                cutPeriodSteps: plan.cutPeriodSteps,
                robotManifestPath: robotManifestPath,
                kp: plan.kp,
                kd: plan.kd,
                yawDamping: plan.yawDamping,
                hoverScale: plan.hoverScale
            )
        }
    }
}
