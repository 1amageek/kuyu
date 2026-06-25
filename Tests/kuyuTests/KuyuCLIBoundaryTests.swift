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

@Test func trainingHarnessSummaryDelegatesCandidateSelectionToReferenceOwnerService() throws {
    let cliSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let commandSource = try extractSource(
        cliSource,
        from: "struct CheckTrainingHarness",
        to: "struct CheckTrainingHarnessSweep"
    )

    #expect(commandSource.contains("harnessGateService.requiredTasksSatisfied"))
    #expect(commandSource.contains("harnessGateService.selectedCandidate"))
    #expect(cliSource.contains("ReferenceQuadrotorTrainingHarnessProbeSelectionInput"))
    #expect(!cliSource.contains("selectedHarnessCandidate"))
    #expect(!cliSource.contains("CheckTrainingHarnessSelectedCandidate"))
    #expect(!cliSource.contains("selectedCheckpointRole == \"candidate\""))
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

@Test func appAdaptersDelegateReferenceQuadrotorParameterResolutionToReferenceOwnerService() throws {
    let cliSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let conformanceSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/ConformanceCommand.swift", isDirectory: false),
        encoding: .utf8
    )
    let runnerServiceSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Services/SimulationRunnerService.swift", isDirectory: false),
        encoding: .utf8
    )
    let viewModelSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Model/SimulationViewModel.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(cliSource.contains("ReferenceQuadrotorParameterResolutionService().parameters(modelPath: modelPath)"))
    #expect(cliSource.contains("ReferenceQuadrotorParameterResolutionService().parameters("))
    #expect(conformanceSource.contains("ReferenceQuadrotorParameterResolutionService().parameters("))
    #expect(runnerServiceSource.contains("ReferenceQuadrotorParameterResolutionService()"))
    #expect(runnerServiceSource.contains("ReferenceQuadrotorParameterResolutionRequest("))
    #expect(viewModelSource.contains("ReferenceQuadrotorParameterResolutionService().parameters(modelPath: trimmed)"))
    #expect(viewModelSource.contains("ReferenceQuadrotorParameterResolutionService().parameters("))
    #expect(!cliSource.contains("KuyuSingleLiftParameterTuning.tuned"))
    #expect(!conformanceSource.contains("KuyuSingleLiftParameterTuning.tuned"))
    #expect(!runnerServiceSource.contains("KuyuSingleLiftParameterTuning.tuned"))
    #expect(!viewModelSource.contains("KuyuSingleLiftParameterTuning.tuned"))
    #expect(!cliSource.contains("ReferenceQuadrotorParameters.reference("))
    #expect(!conformanceSource.contains("ReferenceQuadrotorParameters.reference("))
    #expect(!runnerServiceSource.contains("ReferenceQuadrotorParameters.reference("))
    #expect(!viewModelSource.contains("ReferenceQuadrotorParameters.reference("))
    #expect(!cliSource.contains("ReferenceQuadrotorParameters.baseline"))
    #expect(!conformanceSource.contains("ReferenceQuadrotorParameters.baseline"))
    #expect(!runnerServiceSource.contains("ReferenceQuadrotorParameters.baseline"))
    #expect(!viewModelSource.contains("ReferenceQuadrotorParameters.baseline"))
}

@Test func roArmM1TrainingCommandDelegatesPipelineToProfileOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/RoArmM1JointTargetTraining.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("RoArmM1ArmGripperTrainingPipelineService("))
    #expect(source.contains("RoArmM1ArmGripperTrainingPipelineService.Request("))
    #expect(source.contains("RoArmM1ArmGripperTrainingPipelineService.ManasTrainingConfig("))
    #expect(source.contains("import KuyuMLXRoArmM1"))
    #expect(source.contains("RoArmM1ArmGripperManasTrainingService("))
    #expect(!source.contains("RoArmM1ArmGripperManasTrainer"))
    #expect(!source.contains("KuyuModelLoader().loadRobot"))
    #expect(!source.contains("RoArmM1JointTargetTrainingGoal.canonical.robotManifestID"))
    #expect(!source.contains("ArticulatedRigidBodySimulationRequest("))
    #expect(!source.contains("ArticulatedRigidBodySimulator().run"))
    #expect(!source.contains("RoArmM1JointTargetTrainingDatasetBuilder"))
    #expect(!source.contains("result.report.passed"))
}

@Test func roArmM1HardwareProbeDelegatesCommandShapingToProfileOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/RoArmM1HardwareProbe.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("RoArmM1HardwareProbeCommandService()"))
    #expect(source.contains("RoArmM1HardwareProbeCommandRequest("))
    #expect(source.contains("RoArmM1HardwareCalibrationPlanRequest("))
    #expect(source.contains("RoArmM1HardwareParityReadinessService().validateReport"))
    #expect(!source.contains("RoArmM1HardwareProbeReadinessService().validate"))
    #expect(!source.contains("RoArmM1HardwareCalibrationPlanBuilder().build"))
    #expect(!source.contains("MotorNerveChain("))
    #expect(!source.contains("DriveIntent("))
    #expect(!source.contains("RoArmM1ServoCommandEncoder("))
    #expect(!source.contains("validateTargets"))
    #expect(!source.contains("activeJointLimits"))
}

@Test func uiAdaptersDelegateStarterCheckpointContractToReferenceOwnerService() throws {
    let viewModelSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Model/SimulationViewModel.swift", isDirectory: false),
        encoding: .utf8
    )
    let preparerSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Services/RunnableProjectAssetPreparer.swift", isDirectory: false),
        encoding: .utf8
    )
    let runnerServiceSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Services/SimulationRunnerService.swift", isDirectory: false),
        encoding: .utf8
    )
    let validatorSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Services/StarterSourceCheckpointValidator.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(viewModelSource.contains("ReferenceQuadrotorStarterCheckpointContractService().contract"))
    #expect(viewModelSource.contains("ReferenceQuadrotorStarterCheckpointContractService()"))
    #expect(viewModelSource.contains(".defaultContract(for: taskMode)"))
    #expect(preparerSource.contains("ReferenceQuadrotorStarterCheckpointContractService().contract"))
    #expect(preparerSource.contains("starterContract.starterActionMean"))
    #expect(runnerServiceSource.contains("ReferenceQuadrotorStarterCheckpointContractService()"))
    #expect(runnerServiceSource.contains(".defaultContract(for: request.taskMode)"))
    #expect(validatorSource.contains("ReferenceQuadrotorStarterCheckpointContractService().contract"))
    #expect(validatorSource.contains("expectedDriveCount: starterContract.expectedDriveCount"))
    #expect(validatorSource.contains("expectedObservationChannelCount: starterContract.expectedObservationChannelCount"))
    #expect(!viewModelSource.contains("starterExpectedDriveCount"))
    #expect(!viewModelSource.contains("starterObservationChannelCount"))
    #expect(!viewModelSource.contains("starterDriveCount"))
    #expect(!preparerSource.contains("starterActionMean(taskMode"))
    #expect(!preparerSource.contains("switch request.taskMode"))
    #expect(!runnerServiceSource.contains("expectedDriveCount: 4"))
    #expect(!runnerServiceSource.contains("expectedDriveCount: 1"))
    #expect(!validatorSource.contains("public let expectedDriveCount"))
    #expect(!validatorSource.contains("public let expectedObservationChannelCount"))
}

@Test func simulationRunnerDelegatesSuiteResultPassClassificationToScenarios() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Services/SimulationRunnerService.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("SuiteRunResultFactory().makeEvaluationOnly"))
    #expect(!source.contains("evaluations.allSatisfy"))
}

@Test func commandSystemDelegatesReferenceTrainingBackendBundleToProfileOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Services/CommandSystem.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("ReferenceQuadrotorTrainingBackendBundleFactory("))
    #expect(source.contains("workerModelStoreFactory: { ManasMLXModelStore() }"))
    #expect(source.contains("robotManifestPath: runRequest.robotManifestPath"))
    #expect(!source.contains("ManasMLXTrainingBackendFactory("))
}

@Test func regressionMatrixDelegatesSummaryPassClassificationToReferenceOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let regressionMatrixSource = try String(extractSource(
        source,
        from: "struct CheckKuyuRegressionMatrix",
        to: "private func runKuyuRegression("
    ))

    #expect(regressionMatrixSource.contains("ReferenceQuadrotorRegressionMatrixSummaryService().makeSummary"))
    #expect(regressionMatrixSource.contains("ReferenceQuadrotorRegressionMatrixSummaryRequest"))
    #expect(!regressionMatrixSource.contains("entries.allSatisfy(\\.accepted)"))
    #expect(!regressionMatrixSource.contains("private struct KuyuRegressionMatrixSummary"))
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
