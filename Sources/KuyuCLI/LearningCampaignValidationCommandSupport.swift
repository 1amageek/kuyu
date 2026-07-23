import Foundation
import KuyuMLX
import KuyuMLXReferenceQuadrotor

func referenceQuadrotorValidationReport(
    artifactRoot: URL,
    policy: LearningCampaignValidationPolicy
) throws -> LearningCampaignValidation {
    let artifactValidator = ReferenceQuadrotorLearningCampaignArtifactValidatorFactory()
        .validator()
    let validationService = LearningCampaignArtifactValidationService {
        artifactRoot, policy, writesValidationArtifact in
        try artifactValidator.validate(
            artifactRoot: artifactRoot,
            policy: policy,
            writesValidationArtifact: writesValidationArtifact
        )
    }
    return try validationService.report(
        for: LearningCampaignArtifactValidationService.Request(
            artifactRoot: artifactRoot,
            policy: policy
        )
    )
}

func printLearningCampaignValidationIssues(
    _ validation: LearningCampaignValidation,
    prefix: String = "learning-campaign-validation"
) {
    print("[\(prefix)] invalid issueCount=\(validation.issueCount)")
    for issue in validation.issues {
        print("[\(prefix)] \(issue.code): \(issue.detail)")
    }
}
