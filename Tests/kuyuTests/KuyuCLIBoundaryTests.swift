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

@Test func evaluateManasCheckpointDelegatesEvaluationPipelineToReferenceOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let commandSource = try extractSource(
        source,
        from: "struct EvaluateManasCheckpoint",
        to: "struct CalibrateManasCheckpoint"
    )

    #expect(commandSource.contains("ReferenceQuadrotorCheckpointEvaluationService().evaluate"))
    #expect(!commandSource.contains("ManasMLXReferenceQuadrotorCheckpointEvaluator("))
    #expect(!commandSource.contains("GeneratedTrainingArtifactCompatibilityVerifier().loadCheckpointEvaluationArtifact"))
    #expect(!commandSource.contains("ReferenceQuadrotorCheckpointEvaluationAcceptanceService()"))
    #expect(!commandSource.contains("private func evaluateCheckpointAcceptanceIfNeeded"))
}

@Test func daggerRelabelDelegatesRolloutRelabelingToReferenceOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let commandSource = try extractSource(
        source,
        from: "struct DaggerRelabelCTBR",
        to: "struct WriteCTBRCheckpoint"
    )

    #expect(commandSource.contains("ReferenceQuadrotorDAggerRelabelService().relabel"))
    #expect(!commandSource.contains("ManasMLXReferenceQuadrotorCheckpointEvaluator("))
    #expect(!commandSource.contains("temporalCTBRRolloutEpisodes"))
    #expect(!commandSource.contains("KuyAtt1Suite().scenarios"))
    #expect(!commandSource.contains("AttitudeRecoveryRelabeler()"))
    #expect(!commandSource.contains("TrainingDatasetWriter().write"))
}

@Test func biasCalibrationDelegatesCheckpointEvaluationPipelineToReferenceOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let commandSource = try extractSource(
        source,
        from: "struct SelectManasBiasCalibration",
        to: "private func createFreshArtifactRoot"
    )

    #expect(commandSource.contains("ReferenceQuadrotorCheckpointEvaluationService()"))
    #expect(commandSource.contains("checkpointEvaluationService.evaluate"))
    #expect(!commandSource.contains("ManasMLXReferenceQuadrotorCheckpointEvaluator("))
    #expect(!commandSource.contains("GeneratedTrainingArtifactCompatibilityVerifier().loadCheckpointEvaluationArtifact"))
    #expect(!commandSource.contains("ReferenceQuadrotorCheckpointEvaluationAcceptanceService()"))
}

@Test func trainingProbeExecutorDelegatesRecoveryRelabelDatasetToReferenceOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let executorSource = try extractSource(
        source,
        from: "private final class CLITrainingProbeExecutor",
        to: "struct EvolveManas"
    )

    #expect(executorSource.contains("ReferenceQuadrotorRecoveryRelabelDatasetService().write"))
    #expect(executorSource.contains("ReferenceQuadrotorRecoveryRelabelDatasetRequest("))
    #expect(!executorSource.contains("KuyAtt1Suite().scenarios"))
    #expect(!executorSource.contains("KuyLiftSuite().scenarios"))
    #expect(!executorSource.contains("KuySingleLiftSuite().scenarios"))
    #expect(!executorSource.contains("AttitudeRecoveryRelabeler()"))
    #expect(!executorSource.contains("LiftRecoveryRelabeler()"))
    #expect(!executorSource.contains("SinglePropRecoveryRelabeler()"))
    #expect(!executorSource.contains("KuyuSingleLiftParameterTuning.tuned"))
    #expect(!executorSource.contains(".write(result:"))
}

private func kuyuPackageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func extractSource(_ source: String, from startMarker: String, to endMarker: String) throws -> Substring {
    let start = try #require(source.range(of: startMarker)?.lowerBound)
    let end = try #require(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
    return source[start..<end]
}
