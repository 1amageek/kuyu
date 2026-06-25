import Foundation
import Testing

@Test func evolveManasRejectsSyntheticCandidateOnlyEvaluation() throws {
    let cliSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(cliSource.contains("--evaluation candidateOnly is unsupported"))
    #expect(cliSource.contains("ReferenceQuadrotorEvolutionRegressionEvaluator("))
    #expect(!cliSource.contains("CLICandidateOnlyEvolutionEvaluator"))
    #expect(!cliSource.contains("preflight mode=lightweight"))
    #expect(!cliSource.contains("taskPassRate: 1"))
    #expect(!cliSource.contains("safetyViolationRate: 0"))
}

@Test func trainingHarnessRetryPolicyDelegatesToReferenceOwnerService() throws {
    let cliSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(cliSource.contains("harnessGateService.repairSourceCheckpointURL(result: result)"))
    #expect(cliSource.contains("harnessGateService.acceptedRecoveryDatasetURL(result: result)"))
    #expect(!cliSource.contains("private func repairSourceCheckpointURL(from result: TrainingProbeResult)"))
    #expect(!cliSource.contains("private func acceptedRecoveryDatasetURL(from result: TrainingProbeResult)"))
    #expect(!cliSource.contains("private func hasHardSafetyFailure"))
}

@Test func trainCommandDelegatesRunOutcomeCompletionToTrainingRunDriver() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/TrainCommand.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("driver.finish(result: result)"))
    #expect(!source.contains("result.checkpointDecision.state == .accepted"))
    #expect(!source.contains("finishCompleted(acceptedCheckpointPath:"))
    #expect(!source.contains("finishCancelled(acceptedCheckpointPath:"))
}

@Test func learningCampaignDelegatesTerminalAcceptanceToTrainingRunClassifier() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("TrainingRunResultTerminalClassifier().classify(result: result)"))
    #expect(!source.contains("result.checkpointDecision.state == .accepted"))
}

private func kuyuPackageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
