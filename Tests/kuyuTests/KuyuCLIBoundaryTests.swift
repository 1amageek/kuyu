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
    #expect(source.contains("TrainingRunResultTerminalClassifier().classify(result: result)"))
    #expect(source.contains("terminalAcceptance=\\(classification.status.rawValue)"))
    #expect(!source.contains("result.checkpointDecision.state == .accepted"))
    #expect(!source.contains("accepted=\\(result.convergence.accepted)"))
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
    #expect(source.contains("terminalAcceptance=\\(classification.status.rawValue)"))
    #expect(!source.contains("result.checkpointDecision.state == .accepted"))
    #expect(!source.contains("accepted=\\(result.convergence.accepted)"))
}

@Test func trainingLoopEventAdapterDelegatesTerminalAcceptanceToTrainingRunClassifier() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Services/TrainingLoopEventAdapter.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("TrainingRunResultTerminalClassifier().classify(result: result)"))
    #expect(source.contains("passed: classification.accepted"))
    #expect(!source.contains("result.convergence.accepted"))
    #expect(!source.contains("result.manifest.failureReason"))
}

@Test func conformanceCommandDelegatesOverallAcceptanceToScenarioReportFactory() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/ConformanceCommand.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("A1ConformanceReportFactory().makeReport"))
    #expect(!source.contains("private func replayVerified"))
    #expect(!source.contains("let passed = !entries.isEmpty"))
    #expect(!source.contains("A1ConformanceReport("))
}

@Test func controlCommandDelegatesSubmissionPolicyToTrainingRunService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/ControlCommand.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("TrainingRunControlSubmissionService().submit"))
    #expect(!source.contains("reader.liveness()"))
    #expect(!source.contains("reader.latestControlSequence()"))
    #expect(!source.contains("reader.submitControlCommand"))
    #expect(!source.contains("case .finished"))
    #expect(!source.contains("case .interrupted"))
}

@Test func trainingRunsViewModelDelegatesControlSubmissionPolicyToTrainingRunService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Model/TrainingRunsViewModel.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("TrainingRunControlSubmissionService().submit"))
    #expect(!source.contains("reader.submitControlCommand"))
    #expect(!source.contains("TrainingRunControlCommand("))
    #expect(!source.contains("case .finished"))
    #expect(!source.contains("case .interrupted"))
    #expect(!source.contains("runAlreadyFinished"))
    #expect(!source.contains("writerProcessDead"))
}

private func kuyuPackageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
