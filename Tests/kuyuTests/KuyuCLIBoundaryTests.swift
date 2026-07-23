import Foundation
import Testing

@Test func learningCampaignCLIUsesAttitudeRRPPOAsItsExecutableDefault() throws {
    let root = kuyuPackageRoot()
    let commandSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/KuyuCLI/RunLearningCampaignCommand.swift",
            isDirectory: false
        ),
        encoding: .utf8
    )
    let executionSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/KuyuCLI/RunLearningCampaignCommand+Execution.swift",
            isDirectory: false
        ),
        encoding: .utf8
    )

    #expect(commandSource.contains("var task: LearningCampaignTask = .attitude"))
    #expect(executionSource.contains("contracts.supportsReinforcementWarmup && !noReinforcementWarmup"))
    #expect(executionSource.contains("try contracts.validate(reinforcement: configuration.reinforcement)"))
}

@Test func evolveManasRejectsSyntheticCandidateOnlyEvaluation() throws {
    let commandSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/EvolveManasCommand.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(commandSource.contains("--evaluation candidateOnly is unsupported"))
    #expect(commandSource.contains("ReferenceQuadrotorEvolutionRegressionEvaluator("))
    #expect(!commandSource.contains("CLICandidateOnlyEvolutionEvaluator"))
    #expect(!commandSource.contains("preflight mode=lightweight"))
    #expect(!commandSource.contains("taskPassRate: 1"))
    #expect(!commandSource.contains("safetyViolationRate: 0"))
}

@Test func evolveManasDelegatesEvolutionPublicationAcceptanceToTrainingVerifier() throws {
    let commandSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/EvolveManasCommand.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(commandSource.contains("let artifactReader = KuyuCLITrainingArtifactReader()"))
    #expect(commandSource.contains("artifactReader.validatedEvolutionPublication"))
    #expect(commandSource.contains("artifactReader.requireAcceptedEvolutionCheckpoint"))
    #expect(!commandSource.contains("artifacts.acceptedCheckpoint.accepted"))
    #expect(!commandSource.contains("artifacts.acceptedCheckpoint.checkpointURL"))
    #expect(!commandSource.contains("artifacts.acceptedCheckpoint.candidateID"))
    #expect(!commandSource.contains("artifacts.acceptedCheckpoint.bestCandidateID"))
    #expect(!commandSource.contains("artifacts.acceptedCheckpoint.bestCheckpointURL"))
    #expect(!commandSource.contains("artifacts.acceptedCheckpoint.reasons"))
    #expect(!commandSource.contains("EvolutionAcceptedCheckpointDecision.fileName"))
}

@Test func cliTrainingArtifactConsumptionGoesThroughTypedReader() throws {
    let root = kuyuPackageRoot()
    let cliSource = try String(
        contentsOf: root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let evolveSource = try String(
        contentsOf: root.appendingPathComponent("Sources/KuyuCLI/EvolveManasCommand.swift", isDirectory: false),
        encoding: .utf8
    )
    let probeSource = try String(
        contentsOf: root.appendingPathComponent("Sources/KuyuCLI/ProbeManasCommand.swift", isDirectory: false),
        encoding: .utf8
    )
    let readerSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/KuyuCLI/KuyuCLITrainingArtifactReader.swift",
            isDirectory: false
        ),
        encoding: .utf8
    )
    let commandSource = cliSource + "\n" + evolveSource

    #expect(commandSource.contains("KuyuCLITrainingArtifactReader().validatedProbeArtifacts"))
    #expect(commandSource.contains("artifactReader.validatedEvolutionPublication"))
    #expect(commandSource.contains("artifactReader.requireAcceptedEvolutionCheckpoint"))
    #expect(!commandSource.contains("GeneratedTrainingArtifactCompatibilityVerifier().validatedProbeArtifacts"))
    #expect(!commandSource.contains("GeneratedTrainingArtifactCompatibilityVerifier().validatedEvolutionArtifacts"))
    #expect(!commandSource.contains("GeneratedTrainingArtifactCompatibilityVerifier.VerificationError"))
    #expect(readerSource.contains("GeneratedTrainingArtifactCompatibilityVerifier"))
    #expect(readerSource.contains("ManasMLXProbeAcceptanceValidator"))
    #expect(readerSource.contains("func validatedProbeArtifacts"))
    #expect(readerSource.contains("func validatedManasMLXProbeAcceptance"))
    #expect(readerSource.contains("func validatedEvolutionPublication"))
    #expect(readerSource.contains("func requireAcceptedEvolutionCheckpoint"))
    #expect(probeSource.contains("artifactReader.validatedManasMLXProbeAcceptance"))
}

@Test func evolveManasCommandLivesOutsideKuyuCLI() throws {
    let root = kuyuPackageRoot()
    let cliURL = root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false)
    let commandURL = root.appendingPathComponent("Sources/KuyuCLI/EvolveManasCommand.swift", isDirectory: false)
    let cliSource = try String(contentsOf: cliURL, encoding: .utf8)
    let commandSource = try String(contentsOf: commandURL, encoding: .utf8)
    let commandLineCount = commandSource.split(separator: "\n", omittingEmptySubsequences: false).count

    #expect(cliSource.contains("EvolveManas.self"))
    #expect(!cliSource.contains("struct EvolveManas"))
    #expect(!cliSource.contains("EvolutionRunOrchestrator("))
    #expect(!cliSource.contains("ReferenceQuadrotorEvolutionRegressionEvaluator("))
    #expect(commandSource.contains("struct EvolveManas"))
    #expect(commandSource.contains("EvolutionRunOrchestrator("))
    #expect(commandSource.contains("ReferenceQuadrotorEvolutionRegressionEvaluator("))
    #expect(commandSource.contains("artifactReader.validatedEvolutionPublication"))
    #expect(commandSource.contains("artifactReader.requireAcceptedEvolutionCheckpoint"))
    #expect(commandSource.contains("candidateOnly is unsupported"))
    #expect(commandLineCount <= 420)
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
    let root = kuyuPackageRoot()
    let cliSource = try String(
        contentsOf: root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let supportSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/TrainingHarnessSupport.swift", isDirectory: false),
        encoding: .utf8
    )
    let commandSource = try extractSource(
        cliSource,
        from: "struct CheckTrainingHarness",
        to: "struct CheckTrainingHarnessSweep"
    )

    #expect(commandSource.contains("harnessGateService.requiredTasksSatisfied"))
    #expect(commandSource.contains("harnessGateService.selectedCandidate"))
    #expect(commandSource.contains("harnessGateService.attemptDecision"))
    #expect(commandSource.contains("attemptDecision.accepted"))
    #expect(supportSource.contains("ReferenceQuadrotorTrainingHarnessProbeSelectionInput"))
    #expect(!commandSource.contains("gateReport.accepted"))
    #expect(!cliSource.contains("selectedHarnessCandidate"))
    #expect(!cliSource.contains("CheckTrainingHarnessSelectedCandidate"))
    #expect(!cliSource.contains("selectedCheckpointRole == \"candidate\""))
}

@Test func trainingHarnessSweepDelegatesAttemptAcceptanceToReferenceOwnerService() throws {
    let cliSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let commandSource = try extractSource(
        cliSource,
        from: "struct CheckTrainingHarnessSweep",
        to: "struct CheckKuyuRegression"
    )

    #expect(commandSource.contains("harnessGateService.attemptDecision"))
    #expect(commandSource.contains("preRegressionDecision.accepted"))
    #expect(commandSource.contains("attemptDecision.accepted"))
    #expect(commandSource.contains("attemptDecision.rejectionReasons"))
    #expect(commandSource.contains("acceptedTasks[attemptDecision.task] = attemptDecision.attempt"))
    #expect(!commandSource.contains("preRegressionGateReport.accepted"))
    #expect(!commandSource.contains("gateReport.accepted"))
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
            .appendingPathComponent("Sources/KuyuCLI/RunLearningCampaignSupport.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("TrainingRunResultTerminalClassifier().classify(result: result)"))
    #expect(source.contains("terminalAcceptance=\\(classification.status.rawValue)"))
    #expect(!source.contains("result.checkpointDecision.state == .accepted"))
    #expect(!source.contains("accepted=\\(result.convergence.accepted)"))
}

@Test func conformanceCommandDelegatesOverallAcceptanceToScenarioReportFactory() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/ConformanceCommand.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("A1ConformanceReportFactory().makeReport"))
    #expect(source.contains("KuyAtt1RunOutputFactory().makeOutput"))
    #expect(!source.contains("private func replayVerified"))
    #expect(!source.contains("let passed = !entries.isEmpty"))
    #expect(!source.contains("ValidationSummary("))
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
        to: "struct RunFoundationAcceptance"
    )

    #expect(commandSource.contains("ReferenceQuadrotorCheckpointEvaluationService().evaluate"))
    #expect(!commandSource.contains("ManasMLXReferenceQuadrotorCheckpointEvaluator("))
    #expect(!commandSource.contains("GeneratedTrainingArtifactCompatibilityVerifier().validatedCheckpointEvaluationArtifact"))
    #expect(!commandSource.contains("ReferenceQuadrotorCheckpointEvaluationAcceptanceService()"))
    #expect(!commandSource.contains("private func evaluateCheckpointAcceptanceIfNeeded"))
}

@Test func foundationAcceptanceDelegatesPipelineToReferenceOwnerService() throws {
    let root = kuyuPackageRoot()
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let supportSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/RunFoundationAcceptanceSupport.swift", isDirectory: false),
        encoding: .utf8
    )
    let evidenceConfigurationSource = try String(
        contentsOf: kuyuPackageRoot().appendingPathComponent(
            "Sources/KuyuCLI/FoundationAcceptanceEvidenceConfiguration.swift",
            isDirectory: false
        ),
        encoding: .utf8
    )
    let commandSource = try extractSource(
        source,
        from: "struct RunFoundationAcceptance",
        to: "struct CheckEnvironments"
    )

    #expect(commandSource.contains("ReferenceQuadrotorFoundationAcceptanceService().run"))
    #expect(commandSource.contains("ReferenceQuadrotorFoundationAcceptanceRequest("))
    #expect(supportSource.contains("ReferenceQuadrotorFoundationSourceCheckpointService().write"))
    #expect(commandSource.contains("writeDefaultSourceCheckpoint"))
    #expect(commandSource.contains("foundationAcceptanceCampaignSource"))
    #expect(commandSource.contains("completedCampaignArtifactRootPath"))
    #expect(commandSource.contains("campaignSource: campaignSource"))
    #expect(commandSource.contains("foundationAcceptanceEvidenceConfiguration"))
    #expect(commandSource.contains("configuration: evidenceConfiguration"))
    #expect(evidenceConfigurationSource.contains("ReferenceQuadrotorFoundationCompletedCampaignLoader().load"))
    #expect(evidenceConfigurationSource.contains("tier: plan.tier"))
    #expect(evidenceConfigurationSource.contains("robotManifestPath: robotManifestPath"))
    #expect(supportSource.contains("tier: configuration.tier"))
    #expect(supportSource.contains("KuyuModelLoader().loadRobot(path: configuration.robotManifestPath)"))
    #expect(supportSource.contains("ReferenceQuadrotorFoundationStressSuiteManifestService().write"))
    #expect(commandSource.contains("writeDefaultStressSuiteManifest"))
    #expect(commandSource.contains("defaultStressScenarioSuite"))
    #expect(supportSource.contains("coverageMode: defaultStressScenarioSuite ? .scenarioSuite : .referenceM2Benchmark"))
    #expect(commandSource.contains("m2BenchmarkEnabled: m2Benchmark"))
    #expect(commandSource.contains("m2BenchmarkRequired: !m2Optional"))
    #expect(commandSource.contains("stressSuiteEvidenceRequired: !stressSuiteOptional"))
    #expect(commandSource.contains("stressSuiteManifestURLs: selectedStressSuiteManifestURLs"))
    #expect(supportSource.contains("--physics-corpus-acceptance-artifacts"))
    #expect(commandSource.contains("parseFoundationAcceptancePhysicsCorpusAcceptanceURLs"))
    #expect(commandSource.contains("writeDefaultPhysicsCorpusAcceptance"))
    #expect(supportSource.contains("defaultFoundationPhysicsCorpusAcceptanceURL"))
    #expect(supportSource.contains("LoadedRobotDescriptorCorpusAcceptanceService().write"))
    #expect(commandSource.contains("artifactRoot: artifactRoot"))
    #expect(commandSource.contains("appendFoundationAcceptancePhysicsCorpusAcceptanceURL"))
    #expect(commandSource.contains("physicsCorpusAcceptanceURLs: selectedPhysicsCorpusAcceptanceURLs"))
    #expect(commandSource.contains("incumbentProjectEvidencePackDirectory: incumbentProjectEvidencePackDirectory"))
    #expect(commandSource.contains("ReferenceQuadrotorFoundationAcceptanceArtifactValidator()"))
    #expect(commandSource.contains(".validatedArtifact(in: artifactRoot)"))
    #expect(!commandSource.contains("let artifact = result.artifact"))
    #expect(!commandSource.contains("StressSuiteManifest.referenceQuadrotor"))
    #expect(!commandSource.contains("ReferenceQuadrotorScenarioCatalog.scenarios"))
    #expect(!commandSource.contains("LearningCampaignRunner("))
    #expect(!commandSource.contains("LearningCampaignAcceptedCheckpointResolver("))
    #expect(!commandSource.contains("ReferenceQuadrotorCheckpointEvaluationService().evaluate"))
    #expect(!commandSource.contains("ReferenceQuadrotorG1AttitudeAcceptanceGate"))
}

@Test func foundationAcceptanceSupportLivesOutsideKuyuCLI() throws {
    let root = kuyuPackageRoot()
    let cliURL = root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false)
    let supportURL = root.appendingPathComponent(
        "Sources/KuyuCLI/RunFoundationAcceptanceSupport.swift",
        isDirectory: false
    )
    let cliSource = try String(contentsOf: cliURL, encoding: .utf8)
    let supportSource = try String(contentsOf: supportURL, encoding: .utf8)
    let supportLineCount = supportSource.split(separator: "\n", omittingEmptySubsequences: false).count

    #expect(cliSource.contains("struct RunFoundationAcceptance"))
    #expect(cliSource.contains("ReferenceQuadrotorFoundationAcceptanceService().run"))
    #expect(!cliSource.contains("func validatePositiveFoundationAcceptanceInputs"))
    #expect(!cliSource.contains("func parseFoundationAcceptanceSeeds"))
    #expect(!cliSource.contains("func writeDefaultFoundationSourceCheckpoint"))
    #expect(!cliSource.contains("func writeDefaultFoundationPhysicsCorpusAcceptance"))
    #expect(!cliSource.contains("static func printFoundationAcceptanceEvent"))
    #expect(supportSource.contains("extension RunFoundationAcceptance"))
    #expect(supportSource.contains("func validatePositiveFoundationAcceptanceInputs"))
    #expect(supportSource.contains("func parseFoundationAcceptanceSeeds"))
    #expect(supportSource.contains("func writeDefaultFoundationSourceCheckpoint"))
    #expect(supportSource.contains("func writeDefaultFoundationPhysicsCorpusAcceptance"))
    #expect(supportSource.contains("static func printFoundationAcceptanceEvent"))
    #expect(supportLineCount <= 380)
}

@Test func m2BenchmarkDelegatesPassDecisionToReferenceOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/BenchmarkReferenceAttitudeM2Command.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("ReferenceQuadrotorM2BenchmarkService().run"))
    #expect(source.contains("ReferenceQuadrotorM2BenchmarkRequest("))
    #expect(source.contains("result.decision.allPassed"))
    #expect(!source.contains("result.artifact.suiteSummaries.allSatisfy"))
    #expect(!source.contains("summary.taskPassCount == summary.episodeCount"))
    #expect(!source.contains("summary.violationCount == 0"))
}

@Test func m2BenchmarkCommandLivesOutsideKuyuCLI() throws {
    let root = kuyuPackageRoot()
    let cliURL = root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false)
    let commandURL = root.appendingPathComponent("Sources/KuyuCLI/BenchmarkReferenceAttitudeM2Command.swift", isDirectory: false)
    let cliSource = try String(contentsOf: cliURL, encoding: .utf8)
    let commandSource = try String(contentsOf: commandURL, encoding: .utf8)
    let commandLineCount = commandSource.split(separator: "\n", omittingEmptySubsequences: false).count

    #expect(cliSource.contains("BenchmarkReferenceAttitudeM2.self"))
    #expect(!cliSource.contains("struct BenchmarkReferenceAttitudeM2"))
    #expect(!cliSource.contains("ReferenceQuadrotorM2BenchmarkService().run"))
    #expect(commandSource.contains("struct BenchmarkReferenceAttitudeM2"))
    #expect(commandSource.contains("benchmark-reference-attitude-m2"))
    #expect(commandSource.contains("ReferenceQuadrotorM2BenchmarkService().run"))
    #expect(commandSource.contains("result.decision.allPassed"))
    #expect(commandLineCount <= 180)
}

@Test func loopCommandLivesOutsideKuyuCLI() throws {
    let root = kuyuPackageRoot()
    let cliURL = root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false)
    let commandURL = root.appendingPathComponent("Sources/KuyuCLI/LoopCommand.swift", isDirectory: false)
    let cliSource = try String(contentsOf: cliURL, encoding: .utf8)
    let commandSource = try String(contentsOf: commandURL, encoding: .utf8)
    let commandLineCount = commandSource.split(separator: "\n", omittingEmptySubsequences: false).count

    #expect(cliSource.contains("Loop.self"))
    #expect(!cliSource.contains("struct Loop"))
    #expect(!cliSource.contains("TrainingRunOrchestrator("))
    #expect(!cliSource.contains("[loop]"))
    #expect(commandSource.contains("struct Loop"))
    #expect(commandSource.contains("TrainingRunOrchestrator("))
    #expect(commandSource.contains("ManasMLXTrainingBackend("))
    #expect(commandSource.contains("TrainingRunResultTerminalClassifier().classify(result: result)"))
    #expect(commandLineCount <= 210)
}

@Test func rolloutCommandLivesOutsideKuyuCLI() throws {
    let root = kuyuPackageRoot()
    let cliURL = root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false)
    let commandURL = root.appendingPathComponent("Sources/KuyuCLI/RolloutCommand.swift", isDirectory: false)
    let cliSource = try String(contentsOf: cliURL, encoding: .utf8)
    let commandSource = try String(contentsOf: commandURL, encoding: .utf8)
    let commandLineCount = commandSource.split(separator: "\n", omittingEmptySubsequences: false).count

    #expect(cliSource.contains("Rollout.self"))
    #expect(!cliSource.contains("struct Rollout"))
    #expect(!cliSource.contains("[rollout]"))
    #expect(!cliSource.contains("TrainingDatasetWriter()"))
    #expect(!cliSource.contains("printRolloutSummary"))
    #expect(commandSource.contains("struct Rollout"))
    #expect(commandSource.contains("RolloutRunner("))
    #expect(commandSource.contains("ParallelRolloutCollector("))
    #expect(commandSource.contains("TrainingDatasetWriter()"))
    #expect(commandLineCount <= 230)
}

@Test func probeManasCommandLivesOutsideKuyuCLI() throws {
    let root = kuyuPackageRoot()
    let cliURL = root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false)
    let commandURL = root.appendingPathComponent("Sources/KuyuCLI/ProbeManasCommand.swift", isDirectory: false)
    let supportURL = root.appendingPathComponent("Sources/KuyuCLI/TrainingHarnessSupport.swift", isDirectory: false)
    let cliSource = try String(contentsOf: cliURL, encoding: .utf8)
    let commandSource = try String(contentsOf: commandURL, encoding: .utf8)
    let supportSource = try String(contentsOf: supportURL, encoding: .utf8)
    let commandLineCount = commandSource.split(separator: "\n", omittingEmptySubsequences: false).count

    #expect(cliSource.contains("ProbeManas.self"))
    #expect(!cliSource.contains("struct ProbeManas:"))
    #expect(!cliSource.contains("TrainingProbeOrchestrator("))
    #expect(commandSource.contains("struct ProbeManas"))
    #expect(commandSource.contains("runCLIManasProbe("))
    #expect(commandSource.contains("let artifactReader = KuyuCLITrainingArtifactReader()"))
    #expect(commandSource.contains("artifactReader.validatedProbeArtifacts(in: artifactRoot)"))
    #expect(!commandSource.contains("TrainingProbeOrchestrator("))
    #expect(supportSource.contains("ManasMLXTrainingProbeService().run"))
    #expect(!supportSource.contains("TrainingProbeOrchestrator("))
    #expect(commandLineCount <= 160)
}

@Test func publishWorldModelFusedEvidenceDelegatesPublicationToWorldModelOwnerService() throws {
    let cliSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/WorldModelCommand.swift", isDirectory: false),
        encoding: .utf8
    )
    let commandStart = try #require(source.range(of: "struct PublishWorldModelFusedEvidence")?.lowerBound)
    let commandSource = source[commandStart...]

    #expect(cliSource.contains("PublishWorldModelFusedEvidence.self"))
    #expect(commandSource.contains("MLXRuntimeReadinessService().check"))
    #expect(commandSource.contains("DatasetBackedFusedLongHorizonPublicationRequest("))
    #expect(commandSource.contains("DatasetBackedFusedLongHorizonEvidenceService().publication"))
    #expect(commandSource.contains("publication.artifactURL"))
    #expect(commandSource.contains("publication.physicsGroundedImaginationArtifactURL"))
    #expect(!commandSource.contains("FusedEnvironmentLongHorizonArtifact.fileName"))
    #expect(!commandSource.contains("StateWorldModel("))
    #expect(!commandSource.contains("TrainingDatasetContractValidator"))
    #expect(!commandSource.contains("MLX.loadArrays"))
}

@Test func imagineTrainPublishesFusedEvidenceThroughM2OwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/WorldModelCommand.swift", isDirectory: false),
        encoding: .utf8
    )
    let commandSource = try extractSource(
        source,
        from: "struct ImagineTrain",
        to: "struct PublishWorldModelFusedEvidence"
    )

    #expect(commandSource.contains("M2ImaginationFusedEvidenceRequest("))
    #expect(commandSource.contains("service.publishFusedEvidenceFromImaginationTraining"))
    #expect(commandSource.contains("fusedEvidenceOutputPath"))
    #expect(commandSource.contains("datasetIndex != 0"))
    #expect(commandSource.contains("startRecordIndex != 0"))
    #expect(commandSource.contains("result.imaginationManifestURL"))
    #expect(commandSource.contains("result.physicsGroundedImaginationArtifactURL"))
    #expect(commandSource.contains("result.fusedEvidenceArtifactURL"))
    #expect(commandSource.contains("result.projectEvidencePublication.projectEvidencePackURL"))
    #expect(commandSource.contains("result.projectEvidencePublication.projectEvidencePack.projectID"))
    #expect(!commandSource.contains("FusedEnvironmentLongHorizonArtifact.fileName"))
    #expect(!commandSource.contains("DatasetBackedFusedLongHorizonEvidenceService().publish"))
    #expect(!commandSource.contains("StateWorldModel("))
    #expect(!commandSource.contains("TrainingDatasetContractValidator"))
    #expect(!commandSource.contains("MLX.loadArrays"))
}

@Test func worldModelCommandsLiveOutsideKuyuCLI() throws {
    let root = kuyuPackageRoot()
    let cliURL = root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false)
    let commandURL = root.appendingPathComponent("Sources/KuyuCLI/WorldModelCommand.swift", isDirectory: false)
    let cliSource = try String(contentsOf: cliURL, encoding: .utf8)
    let commandSource = try String(contentsOf: commandURL, encoding: .utf8)
    let commandLineCount = commandSource.split(separator: "\n", omittingEmptySubsequences: false).count

    #expect(cliSource.contains("TrainWorldModel.self"))
    #expect(cliSource.contains("ImagineTrain.self"))
    #expect(cliSource.contains("PublishWorldModelFusedEvidence.self"))
    #expect(!cliSource.contains("struct TrainWorldModel"))
    #expect(!cliSource.contains("struct ImagineTrain"))
    #expect(!cliSource.contains("struct PublishWorldModelFusedEvidence"))
    #expect(commandSource.contains("struct TrainWorldModel"))
    #expect(commandSource.contains("struct ImagineTrain"))
    #expect(commandSource.contains("struct PublishWorldModelFusedEvidence"))
    #expect(commandSource.contains("M2TrainingService().trainWorldModel"))
    #expect(commandSource.contains("service.publishFusedEvidenceFromImaginationTraining"))
    #expect(commandSource.contains("DatasetBackedFusedLongHorizonEvidenceService().publication"))
    #expect(commandLineCount <= 230)
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
    let cliSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/BiasCalibrationCommand.swift", isDirectory: false),
        encoding: .utf8
    )
    let commandSource = try extractSource(
        source,
        from: "struct SelectManasBiasCalibration",
        to: "private func createFreshBiasCalibrationArtifactRoot"
    )

    #expect(cliSource.contains("SelectManasBiasCalibration.self"))
    #expect(commandSource.contains("ReferenceQuadrotorCheckpointEvaluationService()"))
    #expect(commandSource.contains("checkpointEvaluationService.evaluate"))
    #expect(!commandSource.contains("ManasMLXReferenceQuadrotorCheckpointEvaluator("))
    #expect(!commandSource.contains("GeneratedTrainingArtifactCompatibilityVerifier().validatedCheckpointEvaluationArtifact"))
    #expect(!commandSource.contains("ReferenceQuadrotorCheckpointEvaluationAcceptanceService()"))
}

@Test func biasCalibrationCommandsLiveOutsideKuyuCLI() throws {
    let root = kuyuPackageRoot()
    let cliURL = root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false)
    let commandURL = root.appendingPathComponent("Sources/KuyuCLI/BiasCalibrationCommand.swift", isDirectory: false)
    let cliSource = try String(contentsOf: cliURL, encoding: .utf8)
    let commandSource = try String(contentsOf: commandURL, encoding: .utf8)
    let commandLineCount = commandSource.split(separator: "\n", omittingEmptySubsequences: false).count

    #expect(cliSource.contains("CalibrateManasCheckpoint.self"))
    #expect(cliSource.contains("SelectManasBiasCalibration.self"))
    #expect(!cliSource.contains("struct CalibrateManasCheckpoint"))
    #expect(!cliSource.contains("struct SelectManasBiasCalibration"))
    #expect(!cliSource.contains("func parseRawBiasDeltas"))
    #expect(!cliSource.contains("func parseCalibrationSuites"))
    #expect(commandSource.contains("struct CalibrateManasCheckpoint"))
    #expect(commandSource.contains("struct SelectManasBiasCalibration"))
    #expect(commandSource.contains("ManasMLXCheckpointBiasCalibrationService().calibrate"))
    #expect(commandSource.contains("ReferenceQuadrotorBiasCalibrationSelectionService()"))
    #expect(commandSource.contains("selectionService.summarize"))
    #expect(commandLineCount <= 300)
}

@Test func trainingProbeAdapterDelegatesExecutionToMLXService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/TrainingHarnessSupport.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("import KuyuMLXTrainingProbe"))
    #expect(source.contains("ManasMLXTrainingProbeService().run"))
    #expect(source.contains("ManasMLXTrainingProbeRequest("))
    #expect(!source.contains("final class CLITrainingProbeExecutor"))
    #expect(!source.contains("ReferenceQuadrotorRecoveryRelabelDatasetService().write"))
    #expect(!source.contains("ManasMLXTrainingBackend("))
    #expect(!source.contains("TrainingProbeOrchestrator("))
}

@Test func trainingHarnessSupportLivesOutsideKuyuCLI() throws {
    let root = kuyuPackageRoot()
    let cliURL = root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false)
    let supportURL = root.appendingPathComponent("Sources/KuyuCLI/TrainingHarnessSupport.swift", isDirectory: false)
    let cliSource = try String(contentsOf: cliURL, encoding: .utf8)
    let supportSource = try String(contentsOf: supportURL, encoding: .utf8)
    let supportLineCount = supportSource.split(separator: "\n", omittingEmptySubsequences: false).count

    #expect(cliSource.contains("CheckTrainingHarness.self"))
    #expect(cliSource.contains("CheckTrainingHarnessSweep.self"))
    #expect(cliSource.contains("runCLIManasProbe("))
    #expect(!cliSource.contains("final class CLITrainingProbeExecutor"))
    #expect(!cliSource.contains("struct CheckTrainingHarnessProbeEntry"))
    #expect(!cliSource.contains("func parseProbeTasks"))
    #expect(supportSource.contains("ManasMLXTrainingProbeService().run"))
    #expect(!supportSource.contains("final class CLITrainingProbeExecutor"))
    #expect(supportSource.contains("struct CheckTrainingHarnessProbeEntry"))
    #expect(supportSource.contains("func parseProbeTasks"))
    #expect(supportLineCount <= 450)
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
    let viewModelPreflightSource = try extractSource(
        viewModelSource,
        from: "private func preflightParameters(modelPath: String)",
        to: "private func preflightParameters()"
    )

    #expect(cliSource.contains("ReferenceQuadrotorParameterResolutionService().resolvedParameters(modelPath: modelPath)"))
    #expect(cliSource.contains("ReferenceQuadrotorParameterResolutionService().parameters("))
    #expect(conformanceSource.contains("ReferenceQuadrotorParameterResolutionService().parameters("))
    #expect(runnerServiceSource.contains("ReferenceQuadrotorParameterResolutionService()"))
    #expect(runnerServiceSource.contains("ReferenceQuadrotorParameterResolutionRequest("))
    #expect(viewModelPreflightSource.contains("ReferenceQuadrotorParameterResolutionService()"))
    #expect(viewModelPreflightSource.contains(".parameters("))
    #expect(viewModelPreflightSource.contains("modelPath: trimmed"))
    #expect(!cliSource.contains("KuyuSingleLiftParameterTuning.tuned"))
    #expect(!conformanceSource.contains("KuyuSingleLiftParameterTuning.tuned"))
    #expect(!runnerServiceSource.contains("KuyuSingleLiftParameterTuning.tuned"))
    #expect(!viewModelSource.contains("KuyuSingleLiftParameterTuning.tuned"))
    #expect(!cliSource.contains("ReferenceQuadrotorParameters.reference("))
    #expect(!conformanceSource.contains("ReferenceQuadrotorParameters.reference("))
    #expect(!runnerServiceSource.contains("ReferenceQuadrotorParameters.reference("))
    #expect(!viewModelSource.contains("ReferenceQuadrotorParameters.reference("))
    #expect(!cliSource.contains("ReferenceQuadrotorParameters.baseline"))
    #expect(!cliSource.contains("?? .baseline"))
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

@Test func roArmM1HardwareRuntimeCaptureDelegatesTelemetryToProfileOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/RoArmM1HardwareRuntimeCapture.swift", isDirectory: false),
        encoding: .utf8
    )
    let cliSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(cliSource.contains("CaptureRoArmM1HardwareRuntime.self"))
    #expect(source.contains("commandName: \"capture-roarm-m1-hardware-runtime\""))
    #expect(source.contains("let options = try preflightOptions()\n        let loaded = try KuyuModelLoader().loadRobot(path: model)"))
    #expect(source.contains("let rawTraceBinding = try resolvedRawTraceBinding()"))
    #expect(source.contains("guard sampleCount > 0"))
    #expect(source.contains("readTimeoutSeconds.isFinite"))
    #expect(source.contains("--maximum-sample-interval-seconds"))
    #expect(source.contains("--freshness-challenge-lifetime-seconds"))
    #expect(source.contains("maximumSampleIntervalSeconds.isFinite"))
    #expect(source.contains("freshnessChallengeLifetimeSeconds.isFinite"))
    #expect(source.contains("RoArmM1HardwareRuntimeFreshnessChallengeIssuer().challenge"))
    #expect(source.contains("let calibration = try validatedCalibrationReport(path: calibrationReport, loaded: loaded)"))
    #expect(source.contains("let freshnessChallenge = try RoArmM1HardwareRuntimeFreshnessChallengeIssuer().challenge"))
    #expect(source.contains("lifetimeSeconds: options.freshnessChallengeLifetimeSeconds"))
    #expect(source.contains("RoArmM1HardwareRuntimeCapabilityNegotiation.supported("))
    #expect(source.contains("maximumSampleIntervalSeconds: options.maximumSampleIntervalSeconds"))
    #expect(source.contains("capabilityNegotiation: capabilityNegotiation"))
    #expect(source.contains("freshnessChallenge: freshnessChallenge"))
    #expect(source.contains("let freshnessChallengeLifetimeSeconds: Double"))
    #expect(source.contains("publication.log.freshnessChallenge"))
    #expect(source.contains("maxObservedSampleInterval"))
    #expect(source.contains("KuyuModelLoader().loadRobot(path: model)"))
    #expect(source.contains("RoArmM1HardwareParityReadinessService().validateReport"))
    #expect(source.contains("RoArmM1ArmGripperHardwareRuntimeCaptureService().capture"))
    #expect(source.contains("RoArmM1ArmGripperHardwareRuntimeCaptureRequest("))
    #expect(source.contains("devicePath: options.devicePath"))
    #expect(source.contains("expectedSampleCount: options.sampleCount"))
    #expect(source.contains("readTimeoutSeconds: options.readTimeoutSeconds"))
    #expect(source.contains("sessionSource: sessionSource"))
    #expect(source.contains("trustedFirmwareAttestationKeyID"))
    #expect(source.contains("trustedFirmwareAttestationPublicKeyX963"))
    #expect(source.contains("trustedFirmwareKey: options.trustedFirmwareKey"))
    #expect(source.contains("RoArmM1HardwareRuntimeTrustedFirmwareKey("))
    #expect(source.contains("rawTraceBinding: options.rawTraceBinding"))
    #expect(source.contains("resolvedRawTraceBinding()"))
    #expect(source.contains("RoArmM1HardwareRuntimeRawTraceBinding("))
    #expect(source.contains("rawTraceArtifactURL: URL(fileURLWithPath: artifactPath, isDirectory: false)"))
    #expect(source.contains("artifactRoot: URL(fileURLWithPath: rootPath, isDirectory: true)"))
    #expect(source.contains("measurementSystem: calibration.evidence.measurementSystem"))
    #expect(source.contains("measurementDeviceID: calibration.evidence.measurementDeviceID"))
    #expect(source.contains("calibration: calibration"))
    #expect(source.contains("RoArmM1SerialTelemetrySessionSource("))
    #expect(source.contains("publication.log.telemetrySessionID"))
    #expect(!source.contains("RoArmM1ArmGripperHardwareRuntimeLog("))
    #expect(!source.contains("RoArmM1ArmGripperHardwareRuntimeReport("))
    #expect(!source.contains("RoArmM1SerialTelemetryReader"))
    #expect(!source.contains("RoArmM1ArmGripperHardwareRuntimeJSONLinesSampleSource"))
    #expect(!source.contains("Darwin"))
    #expect(!source.contains("termios"))
    #expect(!source.contains("pollfd"))
    #expect(!source.contains("JSONDecoder"))
    #expect(!source.contains("HardwareCalibrationReport"))
    #expect(!source.contains("ManasRuntimeAcceptanceValidator"))
    #expect(!source.contains("ManasModelBundleValidator"))
}

@Test func roArmM1HardwareRuntimePublicationDelegatesEvidenceToProfileOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/RoArmM1HardwareRuntimePublication.swift", isDirectory: false),
        encoding: .utf8
    )
    let cliSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(cliSource.contains("PublishRoArmM1HardwareRuntime.self"))
    #expect(source.contains("commandName: \"publish-roarm-m1-hardware-runtime\""))
    #expect(source.contains("import KuyuMLXRoArmM1"))
    #expect(source.contains("RoArmM1HardwareRuntimeBundleEvidenceService().publish"))
    #expect(source.contains("logURL: logURL"))
    #expect(source.contains("checkpointURL: checkpointURL"))
    #expect(source.contains("reportURL: reportURL"))
    #expect(source.contains("RoArmM1ArmGripperBundleReadinessValidator().validatedBundle"))
    #expect(source.contains("requirement: .hardwareRuntime"))
    #expect(source.contains("bundleScopedURL"))
    #expect(source.contains("readiness.hardwareRuntimeBundleEvidence?.telemetrySessionID"))
    #expect(source.contains("publication.evidenceURL.path"))
    #expect(source.contains("readiness.trainingArtifact.bundleID"))
    #expect(source.contains("readiness.readinessLevel.rawValue"))
    #expect(source.contains("readiness.sourceKind.rawValue"))
    #expect(!source.contains("RoArmM1ArmGripperHardwareRuntimeReportService"))
    #expect(!source.contains("JSONDecoder"))
    #expect(!source.contains("ManasRuntimeAcceptanceValidator"))
    #expect(!source.contains("ManasModelBundleValidator"))
    #expect(!source.contains("ReadinessGate"))
    #expect(!source.contains("HardwareRuntimeReport("))
    #expect(!source.contains("boundedBehaviorSummary()"))
    #expect(!source.contains("hardwareEvidence()"))
}

@Test func roArmM1HardwareCalibrationPublicationDelegatesReportAssemblyToProfileOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/RoArmM1HardwareCalibrationPublication.swift", isDirectory: false),
        encoding: .utf8
    )
    let cliSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(cliSource.contains("PublishRoArmM1HardwareCalibration.self"))
    #expect(source.contains("commandName: \"publish-roarm-m1-hardware-calibration\""))
    #expect(source.contains("RoArmM1HardwareCalibrationReportService().writeReport"))
    #expect(source.contains("RoArmM1HardwareCalibrationReportPublicationRequest("))
    #expect(source.contains("HardwareCalibrationSource("))
    #expect(!source.contains("JSONDecoder"))
    #expect(!source.contains("JSONEncoder"))
    #expect(!source.contains("HardwareCalibrationReport("))
    #expect(!source.contains("RoArmM1ArmGripperHardwareParityEvidence.validated"))
    #expect(!source.contains("RoArmM1HardwareParityReadinessService().validateReport"))
    #expect(!source.contains("ReadinessGate"))
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
    #expect(preparerSource.contains("starterContract.observationContract"))
    #expect(preparerSource.contains("starterContract.starterActionMean"))
    #expect(preparerSource.contains("projectRootURL"))
    #expect(preparerSource.contains("assertCheckpointIsOwned"))
    #expect(preparerSource.contains("resolvingSymlinksInPath()"))
    #expect(preparerSource.contains("checkpointParentPath"))
    #expect(preparerSource.contains("refusingExternalCheckpointPath"))
    #expect(runnerServiceSource.contains("ReferenceQuadrotorStarterCheckpointContractService()"))
    #expect(runnerServiceSource.contains(".defaultContract(for: request.taskMode)"))
    #expect(runnerServiceSource.contains("motorNerveContractRejected"))
    #expect(runnerServiceSource.contains("SimulationRunnerServiceError.motorNerveDriveCountMismatch"))
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
    #expect(!runnerServiceSource.contains("motorNerveFallback"))
    #expect(!runnerServiceSource.contains("fallbackProfile"))
    #expect(!runnerServiceSource.contains("MotorNerveChain disabled"))
    #expect(!validatorSource.contains("public let expectedDriveCount"))
    #expect(!validatorSource.contains("public let expectedObservationChannelCount"))
}

@Test func writeCTBRCheckpointDelegatesStarterContractToReferenceOwnerService() throws {
    let cliSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )
    let commandSource = try extractSource(
        cliSource,
        from: "struct WriteCTBRCheckpoint",
        to: "struct ProbeManasSuite"
    )

    #expect(commandSource.contains("var task: CTBRCheckpointTaskChoice = .attitude"))
    #expect(commandSource.contains("ReferenceQuadrotorStarterCheckpointContractService().contract"))
    #expect(commandSource.contains("observationChannelCountOverride: observationDimension"))
    #expect(commandSource.contains("starterContract.expectedObservationChannelCount"))
    #expect(commandSource.contains("historyLength ?? starterContract.historyLength"))
    #expect(commandSource.contains("starterContract.observationContract"))
    #expect(commandSource.contains("starterContract.starterActionMean"))
    #expect(commandSource.contains("observationSchemaID=\\(manifest.observationSchemaID)"))
    #expect(!commandSource.contains("var observationDimension: Int = 64"))
    #expect(!commandSource.contains("var historyLength: Int = 32"))
    #expect(!commandSource.contains("ReferenceQuadrotorLearningContracts.temporalCTBRObservationContract()"))
}

@Test func simulationRunnerDelegatesSuiteResultPassClassificationToScenarios() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Services/SimulationRunnerService.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("KuyAtt1RunOutputFactory().makeEvaluationOnly"))
    #expect(source.contains("KuyAtt1RunOutputFactory().makeOutput"))
    #expect(source.contains("ArticulatedDynamicScenarioOutputFactory().makeOutput"))
    #expect(!source.contains("evaluations.allSatisfy"))
    #expect(!source.contains("ScenarioEvaluation("))
    #expect(!source.contains("ValidationSummary("))
    #expect(!source.contains("SuiteRunResultFactory()"))
    #expect(!source.contains("KuyAtt1RunOutput(result:"))
    #expect(!source.contains("passed: log.failureReason == nil"))
}

@Test func uiPreviewFactoryDelegatesOutputAssemblyToScenarios() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Preview/KuyuUIPreviewFactory.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("KuyAtt1RunOutputFactory().makeEvaluationOnly"))
    #expect(!source.contains("SuiteRunResult("))
    #expect(!source.contains("ValidationSummary("))
    #expect(!source.contains("KuyAtt1RunOutput(result:"))
}

@Test func cliGracefulStopSignalHandlingUsesTaskInsteadOfDispatchSources() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/RunLearningCampaignSupport.swift", isDirectory: false),
        encoding: .utf8
    )
    let signalSource = try String(extractSource(
        source,
        from: "static func installStopSignalHandlers",
        to: "static func restoreStopSignalHandlers"
    ))
    #expect(signalSource.contains("Task<Void, Never>"))
    #expect(signalSource.contains("learningCampaignStopSignalRequested"))
    #expect(signalSource.contains("Task.sleep"))
    #expect(signalSource.contains("LearningCampaignProcessSignal("))
    #expect(signalSource.contains("await onStopRequested(signal)"))
    #expect(source.contains("_exit(128 + signal)"))
    #expect(!signalSource.contains("DispatchQueue"))
    #expect(!signalSource.contains("DispatchSource"))
    #expect(!signalSource.contains("EventLoopFuture"))
}

@Test func runLearningCampaignCommandLivesOutsideKuyuCLI() throws {
    let root = kuyuPackageRoot()
    let cliURL = root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false)
    let commandURL = root.appendingPathComponent("Sources/KuyuCLI/RunLearningCampaignCommand.swift", isDirectory: false)
    let executionURL = root.appendingPathComponent("Sources/KuyuCLI/RunLearningCampaignCommand+Execution.swift", isDirectory: false)
    let supportURL = root.appendingPathComponent("Sources/KuyuCLI/RunLearningCampaignSupport.swift", isDirectory: false)
    let cliSource = try String(contentsOf: cliURL, encoding: .utf8)
    let commandSource = try String(contentsOf: commandURL, encoding: .utf8)
    let executionSource = try String(contentsOf: executionURL, encoding: .utf8)
    let supportSource = try String(contentsOf: supportURL, encoding: .utf8)

    #expect(cliSource.contains("RunLearningCampaign.self"))
    #expect(!cliSource.contains("struct RunLearningCampaign"))
    #expect(!cliSource.contains("ManasMLXTrainingRunExecutor()"))
    #expect(!cliSource.contains("TrainingRunConfiguration("))
    #expect(commandSource.contains("struct RunLearningCampaign"))
    #expect(commandSource.contains("@Option"))
    #expect(!commandSource.contains("mutating func run"))
    #expect(executionSource.contains("extension RunLearningCampaign"))
    #expect(executionSource.contains("mutating func run"))
    #expect(!executionSource.contains("@Option"))
    #expect(executionSource.contains("ManasMLXTrainingRunProcessExecutor("))
    #expect(executionSource.contains("ManasMLXTrainingWorkerProcessConfigurationFactory().userCache("))
    #expect(!executionSource.contains("let executor = ManasMLXTrainingRunExecutor()"))
    #expect(executionSource.contains("TrainingRunConfiguration("))
    #expect(executionSource.contains("executor.resume"))
    #expect(executionSource.contains("executor.start"))
    #expect(executionSource.contains("resumeSource = .artifactRoot(artifactRoot)"))
    #expect(executionSource.contains("if let resumeSource"))
    #expect(executionSource.contains("source: resumeSource"))
    #expect(executionSource.contains("--resume and --source-checkpoint cannot both be set"))
    #expect(executionSource.contains("ReferenceQuadrotorLearningCampaignTrainingContractResolver()"))
    #expect(executionSource.contains(".contracts(for: task)"))
    #expect(executionSource.contains("ManasMLXModelBundleReferenceResolver()"))
    #expect(!executionSource.contains("bundleID: sourceCheckpointURL.lastPathComponent"))
    #expect(supportSource.contains("static func installStopSignalHandlers"))
    #expect(supportSource.contains("static func restoreStopSignalHandlers"))
    #expect(executionSource.contains("TrainingRunLifecycleCoordinator()"))
    #expect(executionSource.contains("await lifecycle.requestCancellation()"))
    #expect(executionSource.contains("try await lifecycle.register(handle)"))
    #expect(executionSource.contains("lifecycle.waitForTermination()"))
    #expect(executionSource.contains("summary.terminalState == .completed"))
    #expect(supportSource.contains("TrainingRunResultTerminalClassifier().classify(result: result)"))
    #expect(!supportSource.contains("extension LearningCampaignTask"))
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
        to: "struct Verify"
    ))

    #expect(regressionMatrixSource.contains("let matrixSummaryService = ReferenceQuadrotorRegressionMatrixSummaryService()"))
    #expect(regressionMatrixSource.contains("matrixSummaryService.entry"))
    #expect(regressionMatrixSource.contains("matrixSummaryService.failedEntry"))
    #expect(regressionMatrixSource.contains("matrixSummaryService.makeSummary"))
    #expect(regressionMatrixSource.contains("ReferenceQuadrotorRegressionMatrixSummaryRequest"))
    #expect(!regressionMatrixSource.contains("summary.gateReport.accepted"))
    #expect(!regressionMatrixSource.contains("accepted: summary.gateReport.accepted"))
    #expect(!regressionMatrixSource.contains("entries.allSatisfy(\\.accepted)"))
    #expect(!regressionMatrixSource.contains("private struct KuyuRegressionMatrixSummary"))
}

@Test func regressionCommandSupportLivesOutsideKuyuCLI() throws {
    let root = kuyuPackageRoot()
    let cliURL = root.appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false)
    let supportURL = root.appendingPathComponent("Sources/KuyuCLI/RegressionCommandSupport.swift", isDirectory: false)
    let cliSource = try String(contentsOf: cliURL, encoding: .utf8)
    let supportSource = try String(contentsOf: supportURL, encoding: .utf8)
    let supportLineCount = supportSource.split(separator: "\n", omittingEmptySubsequences: false).count

    #expect(cliSource.contains("CheckKuyuRegression.self"))
    #expect(cliSource.contains("CheckKuyuRegressionMatrix.self"))
    #expect(cliSource.contains("runKuyuRegression("))
    #expect(cliSource.contains("writeRegressionMatrixSummary(summary, to: artifactRoot)"))
    #expect(!cliSource.contains("func runKuyuRegression("))
    #expect(!cliSource.contains("func regressionSnapshotURL"))
    #expect(!cliSource.contains("func parseRegressionSuites"))
    #expect(!cliSource.contains("func regressionQualityText"))
    #expect(supportSource.contains("func runKuyuRegression("))
    #expect(supportSource.contains("func regressionSnapshotURL"))
    #expect(supportSource.contains("func parseRegressionSuites"))
    #expect(supportSource.contains("func regressionQualityText"))
    #expect(supportSource.contains("ReferenceQuadrotorRegressionRunner().run"))
    #expect(supportSource.contains("ReferenceQuadrotorRegressionRunConfig("))
    #expect(supportLineCount <= 180)
}

@Test func regressionRunStoreDelegatesInspectionStateToReferenceOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Services/RegressionRunStore.swift", isDirectory: false),
        encoding: .utf8
    )
    let previewSource = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Preview/KuyuUIPreviewFactory.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("typealias PostRegressionGateState = ReferenceQuadrotorRegressionInspectionState"))
    #expect(source.contains("loader.loadInspectionState(from: artifactDirectory)"))
    #expect(previewSource.contains("ReferenceQuadrotorRegressionInspectionRequest"))
    #expect(previewSource.contains("inspectionState("))
    #expect(!previewSource.contains("ReferenceQuadrotorRegressionGatePolicy"))
    #expect(!previewSource.contains("ReferenceQuadrotorRegressionSummary("))
    #expect(!source.contains("rolloutSuites.reduce"))
    #expect(!source.contains("flatMap(\\.workerSummaries)"))
    #expect(!source.contains("taskQuality.map"))
    #expect(!source.contains("gateReport.accepted"))
    #expect(!source.contains("gateReport.qualityGateTask"))
}

@Test func rolloutDefinitionsDelegateScenarioSelectionToReferenceOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuCLI/KuyuCLI.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("ReferenceQuadrotorRolloutScenarioDefinitionFactory().scenarios"))
    #expect(!source.contains("KuyuSingleLiftTrainingSuite" + "().scenarios()"))
    #expect(!source.contains("KuyAtt1Suite" + "().scenarios()"))
    #expect(!source.contains("KuyLiftSuite" + "().scenarios()"))
    #expect(!source.contains("KuySingleLiftSuite" + "().scenarios()"))
    #expect(!source.contains("KUY-SLIFT-TRAIN" + "-M2"))
}

@Test func simulationRunnerDelegatesScenarioSelectionToReferenceOwnerService() throws {
    let source = try String(
        contentsOf: kuyuPackageRoot()
            .appendingPathComponent("Sources/KuyuUI/Services/SimulationRunnerService.swift", isDirectory: false),
        encoding: .utf8
    )

    #expect(source.contains("ReferenceQuadrotorRolloutScenarioDefinitionFactory().scenarios(taskMode:"))
    #expect(!source.contains("KuyAtt1Suite" + "().scenarios()"))
    #expect(!source.contains("KuyLiftSuite" + "().scenarios()"))
    #expect(!source.contains("KuySingleLiftSuite" + "().scenarios()"))
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
