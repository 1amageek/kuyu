import ArgumentParser
import Foundation
import KuyuMLX

struct ValidateLearningCampaign: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate-learning-campaign",
        abstract: "Validate learning campaign artifacts before reusing the final checkpoint."
    )

    @Option(help: "Learning campaign artifact root.")
    var artifactRoot: String

    @Flag(name: .customLong("allow-failed"), help: "Allow failed campaign status while still validating artifact shape.")
    var allowFailed: Bool = false

    @Flag(name: .customLong("allow-running"), help: "Allow validation before campaign-status.json and campaign-finished progress are written.")
    var allowRunning: Bool = false

    mutating func run() async throws {
        let root = URL(fileURLWithPath: artifactRoot, isDirectory: true)
        do {
            let validation = try LearningCampaignArtifactValidator().validate(
                artifactRoot: root,
                allowFailed: allowFailed,
                allowRunning: allowRunning
            )
            print("[learning-campaign-validation] valid artifactRoot=\(validation.artifactRoot)")
        } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
            print("[learning-campaign-validation] invalid issueCount=\(validation.issueCount)")
            for issue in validation.issues {
                print("[learning-campaign-validation] \(issue.code): \(issue.detail)")
            }
            throw ExitCode.failure
        }
    }
}
