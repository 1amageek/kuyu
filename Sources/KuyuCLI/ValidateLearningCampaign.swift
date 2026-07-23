import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXReferenceQuadrotor

struct ValidateLearningCampaign: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate-learning-campaign",
        abstract: "Validate learning campaign artifacts before reusing the final checkpoint."
    )

    @Option(help: "Learning campaign artifact root.")
    var artifactRoot: String

    mutating func run() async throws {
        let root = URL(fileURLWithPath: artifactRoot, isDirectory: true)
        let validation = try referenceQuadrotorValidationReport(
            artifactRoot: root,
            policy: .strict
        )
        if validation.valid {
            print(
                "[learning-campaign-validation] strict-valid receipt=\(validation.receiptContentSHA256) artifactRoot=\(validation.artifactRoot)"
            )
            return
        }
        printLearningCampaignValidationIssues(validation)
        throw ExitCode.failure
    }
}
