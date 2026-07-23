import ArgumentParser
import Foundation
import KuyuMLX

struct DiagnoseLearningCampaign: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnose-learning-campaign",
        abstract: "Inspect incomplete campaign artifacts without authorizing checkpoint reuse."
    )

    @Option(help: "Learning campaign artifact root.")
    var artifactRoot: String

    @Flag(name: .customLong("allow-failed"), help: "Inspect a campaign with failed terminal status.")
    var allowFailed: Bool = false

    @Flag(name: .customLong("allow-running"), help: "Inspect a campaign before terminal artifacts are written.")
    var allowRunning: Bool = false

    mutating func run() async throws {
        let policy = LearningCampaignValidationPolicy(
            allowsFailedCampaign: allowFailed,
            allowsRunningCampaign: allowRunning
        )
        guard !policy.isStrict else {
            throw ValidationError(
                "Diagnostic validation requires --allow-failed, --allow-running, or both."
            )
        }
        let validation = try referenceQuadrotorValidationReport(
            artifactRoot: URL(fileURLWithPath: artifactRoot, isDirectory: true),
            policy: policy
        )
        if validation.valid {
            print(
                "[learning-campaign-diagnosis] diagnostic-only policy=\(policy.rawValue) receipt=\(validation.receiptContentSHA256) artifactRoot=\(validation.artifactRoot)"
            )
            return
        }
        printLearningCampaignValidationIssues(validation, prefix: "learning-campaign-diagnosis")
        throw ExitCode.failure
    }
}
