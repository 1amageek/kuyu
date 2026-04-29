import Foundation
import Testing

@Test func simulationViewModelDoesNotOwnTrainingLoopController() throws {
    let source = try readSource("Sources/KuyuUI/Model/SimulationViewModel.swift")

    #expect(!source.contains("TrainingLoopController("))
    #expect(!source.contains("trainingLoopController"))
}

@Test func configPanelDoesNotBindDescriptorPathDirectly() throws {
    let source = try readSource("Sources/KuyuUI/Views/ConfigPanelView.swift")

    #expect(!source.contains("$model.modelDescriptorPath"))
    #expect(source.contains("setModelDescriptorPath("))
}

@Test func commandSystemOwnsTrainingLoopExecutionBoundary() throws {
    let source = try readSource("Sources/KuyuUI/Services/CommandSystem.swift")
    let trainingService = try readSource("Sources/KuyuUI/Services/TrainingService.swift")

    #expect(source.contains("TrainingLoopController(commandExecutor: self)"))
    #expect(source.contains("extension CommandSystem: TrainingLoopCommandExecuting"))
    #expect(source.contains("TrainingRunOrchestrator("))
    #expect(source.contains("ManasMLXTrainingBackendFactory().makeWorkerLocalBackend"))
    #expect(source.contains("sourceSnapshot: backendBundle.sourceSnapshot"))
    #expect(source.contains("extension CommandSystem: TrainingScenarioExecuting"))
    #expect(source.contains("runSuiteForTrainingRun"))
    #expect(trainingService.contains("ManasMLXTrainingRuntime"))
    #expect(trainingService.contains("TrainingBackendRequest("))
    #expect(!trainingService.contains(".trainCore("))
}

@Test func trainingLoopControllerDelegatesToSharedOrchestratorContract() throws {
    let source = try readSource("Sources/KuyuUI/Services/TrainingLoopController.swift")
    let adapterSource = try readSource("Sources/KuyuUI/Services/TrainingLoopEventAdapter.swift")
    let cliSource = try readSource("Sources/KuyuCLI/KuyuCLI.swift")

    #expect(source.contains("runTrainingRunForTrainingLoop"))
    #expect(source.contains("TrainingRunConfig("))
    #expect(source.contains("TrainingLoopEventAdapter.present"))
    #expect(source.contains("TrainingLoopEventAdapter.presentCompletion"))
    #expect(adapterSource.contains("TrainingRunEvent"))
    #expect(adapterSource.contains("TrainingLoopSummary("))
    #expect(!source.contains("exportDatasetForTrainingLoop"))
    #expect(!source.contains("trainCoreForTrainingLoop"))
    #expect(cliSource.contains("TrainingRunOrchestrator("))
    #expect(cliSource.contains("ProbeManas.self"))
    #expect(cliSource.contains("TrainingProbeOrchestrator("))
    #expect(cliSource.contains("KuyuScenarioRuntime("))
    #expect(!cliSource.contains("probe-manas currently supports attitude only"))
    #expect(cliSource.contains("let scenarioStore = ManasMLXModelStore()"))
    #expect(cliSource.contains("let workerStore = ManasMLXModelStore()"))
    #expect(cliSource.contains("CLIScenarioExecutor("))
}

@Test func serviceDescriptorFailureLogsCarryRequiredMetadataKeys() throws {
    let source = try readSource("Sources/KuyuUI/Services/SimulationRunnerService.swift")

    #expect(source.contains("\"action\": \"descriptorLoadFailed\""))
    #expect(source.contains("\"modelDescriptor\""))
    #expect(source.contains("\"reason\": \"loadFailed\""))
    #expect(source.contains("\"error\""))
}

@Test func simulationViewModelDelegatesDescriptorAndTelemetryProjection() throws {
    let source = try readSource("Sources/KuyuUI/Model/SimulationViewModel.swift")
    let coordinatorSource = try readSource("Sources/KuyuUI/Services/TrainingRunCoordinator.swift")
    let bootstrapSource = try readSource("Sources/KuyuUI/Services/TrainingBootstrapCoordinator.swift")

    #expect(source.contains("DescriptorSelection.resolveForTask"))
    #expect(source.contains("telemetryPresenter.present"))
    #expect(source.contains("descendingIntentResolver.resolve"))
    #expect(source.contains("trainingRunPresenter.runCompleted"))
    #expect(source.contains("checkpointStore.persist"))
    #expect(source.contains("trainingRunCoordinator.prepare"))
    #expect(source.contains("trainingBootstrapCoordinator.makeRequest"))
    #expect(coordinatorSource.contains("TrainingRunPreparationInput"))
    #expect(coordinatorSource.contains("TrainingLoopConfig("))
    #expect(coordinatorSource.contains("SimulationRunRequest("))
    #expect(bootstrapSource.contains("TrainingBootstrapInput"))
    #expect(bootstrapSource.contains("TrainingRequest("))
    #expect(!source.contains("metadata[\"u_out_thrust\"]"))
    #expect(!source.contains("metadata[\"netAccelZ\"]"))
    #expect(!source.contains("private func parseDescending"))
    #expect(!source.contains("ScenarioMetricsBuilder.build"))
    #expect(!source.contains("modelStore.saveModel("))
}

@Test func trainingRunStoreIsArtifactDriven() throws {
    let source = try readSource("Sources/KuyuUI/Services/TrainingRunStore.swift")
    let controllerSource = try readSource("Sources/KuyuUI/Services/TrainingLoopController.swift")
    let adapterSource = try readSource("Sources/KuyuUI/Services/TrainingLoopEventAdapter.swift")
    let viewModelSource = try readSource("Sources/KuyuUI/Model/SimulationViewModel.swift")
    let validatorSource = try readTrainingSource("Sources/KuyuTraining/TrainingRunArtifactValidator.swift")
    let artifactSource = try readTrainingSource("Sources/KuyuTraining/TrainingArtifacts.swift")

    #expect(source.contains("TrainingRunArtifactValidator"))
    #expect(source.contains("TrainingMetricRecord"))
    #expect(source.contains(".validationLoss"))
    #expect(source.contains(".passRate"))
    #expect(source.contains(".failureRate"))
    #expect(source.contains(".safetyViolation"))
    #expect(source.contains(".rewardAverage"))
    #expect(source.contains(".workerThroughput"))
    #expect(artifactSource.contains("artifact-contract.json"))
    #expect(validatorSource.contains("manifest.json"))
    #expect(validatorSource.contains("metrics.jsonl"))
    #expect(validatorSource.contains("convergence.json"))
    #expect(validatorSource.contains("checkpoint-decision.json"))
    #expect(controllerSource.contains("TrainingLoopEventAdapter.presentCompletion"))
    #expect(adapterSource.contains("artifactDirectory: artifactDirectory"))
    #expect(adapterSource.contains("checkpointDecision: result.checkpointDecision"))
    #expect(viewModelSource.contains("trainingRunStore.load"))
    #expect(viewModelSource.contains("lastConvergenceSummary"))
    #expect(viewModelSource.contains("lastCheckpointDecision"))
}

@Test func trainingDashboardShowsLiveLearningHealthAndGateState() throws {
    let viewModelSource = try readSource("Sources/KuyuUI/Model/SimulationViewModel.swift")
    let dashboardSource = try readSource("Sources/KuyuUI/Views/TrainingDashboardView.swift")
    let liveStatusSource = try readSource("Sources/KuyuUI/Model/TrainingLiveStatus.swift")

    #expect(liveStatusSource.contains("struct TrainingLiveStatus"))
    #expect(viewModelSource.contains("trainingLiveStatus"))
    #expect(viewModelSource.contains("trainingTimeline"))
    #expect(viewModelSource.contains("updateRunQualityStatus"))
    #expect(viewModelSource.contains("passRateSamples"))
    #expect(viewModelSource.contains("safetyViolationSamples"))
    #expect(viewModelSource.contains("workerThroughputSamples"))
    #expect(dashboardSource.contains("TrainingLiveHealthPanel"))
    #expect(dashboardSource.contains("TrainingGatePanel"))
    #expect(dashboardSource.contains("TrainingTimelinePanel"))
    #expect(dashboardSource.contains("Pass Rate"))
    #expect(dashboardSource.contains("Safety Violation"))
    #expect(dashboardSource.contains("Worker Throughput"))
}

@Test func cliHarnessUsesProbeSelectedCheckpointContract() throws {
    let cliSource = try readSource("Sources/KuyuCLI/KuyuCLI.swift")
    let probeSource = try readTrainingSource("Sources/KuyuTraining/TrainingProbeOrchestrator.swift")
    let validatorSource = try readTrainingSource("Sources/KuyuTraining/TrainingProbeArtifactValidator.swift")

    #expect(probeSource.contains("selectedCheckpointRole"))
    #expect(probeSource.contains("sourceCheckpointURL"))
    #expect(probeSource.contains("selectedCheckpointURL"))
    #expect(validatorSource.contains("validateSelectedCheckpoint"))
    #expect(validatorSource.contains("candidate checkpoint cannot be selected when probe is rejected"))
    #expect(cliSource.contains("selectedCandidateCheckpointURL(result.comparison)"))
    #expect(cliSource.contains("sourceCheckpointURL(from: sourceCheckpointPath)"))
    #expect(cliSource.contains("repairSourceCheckpointURL(from: result)"))
    #expect(cliSource.contains("currentSourceCheckpointURL = repairSourceCheckpointURL"))
    #expect(cliSource.contains("result.training.checkpointDecision.candidateCheckpointURL"))
    #expect(cliSource.contains("TrainingHarnessGateReport"))
    #expect(cliSource.contains("KuyuRegressionGateReport"))
    #expect(cliSource.contains("gateReport: gateReport"))
    #expect(cliSource.contains("post-regression-failed"))
    #expect(cliSource.contains("post-regression-min-reward-average"))
    #expect(cliSource.contains("min-reward-average"))
    #expect(cliSource.contains("reward-average-below-min"))
    #expect(cliSource.contains("post-regression-reward-average-below-min"))
    #expect(cliSource.contains("postRegressionAcceptanceSatisfied(postRegression)"))
    #expect(cliSource.contains("postRegressionApplicable(regression)"))
    #expect(cliSource.contains("regressionRolloutTask(selectedTasks)"))
    #expect(cliSource.contains("suiteForDefinitions = regressionTask == .attitude ? suite : nil"))
    #expect(cliSource.contains("taskFailureCount == 0"))
    #expect(cliSource.contains("evaluateRegressionEpisodes("))
    #expect(cliSource.contains("selected-checkpoint-not-candidate"))
    #expect(cliSource.contains("teacher-divergence-regression"))
    #expect(!cliSource.contains("?? result.training.checkpointDecision.candidateCheckpointURL"))
}

@Test func cliRegressionGateRequiresTaskPassAndRewardQuality() throws {
    let cliSource = try readSource("Sources/KuyuCLI/KuyuCLI.swift")

    #expect(cliSource.contains("KuyuRegressionGatePolicy.report"))
    #expect(cliSource.contains("taskPassCount != entry.episodeCount"))
    #expect(cliSource.contains("task-pass-mismatch"))
    #expect(cliSource.contains("entry.rewardAverage < minimumRewardAverage"))
    #expect(cliSource.contains("reward-average-below-min"))
    #expect(cliSource.contains("gateReport.accepted"))
    #expect(cliSource.contains("allPassed: gateReport.accepted"))
}

@Test func cliHarnessFeedsRecoveryDatasetsIntoLaterAttempts() throws {
    let cliSource = try readSource("Sources/KuyuCLI/KuyuCLI.swift")
    let trainingSource = try readTrainingSource("Sources/KuyuTraining/TrainingRunOrchestrator.swift")
    let singlePropRelabelerSource = try readTrainingSource("Sources/KuyuTraining/SinglePropRecoveryRelabeler.swift")
    let liftRelabelerSource = try readTrainingSource("Sources/KuyuTraining/LiftRecoveryRelabeler.swift")

    #expect(trainingSource.contains("additionalDatasetURLs"))
    #expect(trainingSource.contains("additionalDatasetRepeatCount"))
    #expect(trainingSource.contains("TrainingDatasetMixer().mix"))
    #expect(cliSource.contains("acceptedRecoveryDatasetURL(from: result)"))
    #expect(cliSource.contains("recoveryDatasetURLs.append(recoveryDatasetURL)"))
    #expect(cliSource.contains("additionalDatasetURLs: recoveryDatasetURLs"))
    #expect(cliSource.contains("additionalDatasetRepeatCount: recoveryRepeat"))
    #expect(cliSource.contains("--recovery-repeat"))
    #expect(cliSource.contains("includeOnlyFailedScenarios: !includeSuccessfulScenarios"))
    #expect(cliSource.contains("includeSuccessfulScenarios: Bool"))
    #expect(cliSource.contains("LiftRecoveryRelabeler()"))
    #expect(cliSource.contains("KuyLiftSuite().scenarios()"))
    #expect(cliSource.contains("SinglePropRecoveryRelabeler()"))
    #expect(cliSource.contains("KuySingleLiftSuite().scenarios()"))
    #expect(singlePropRelabelerSource.contains("SinglePropHoverCut"))
    #expect(liftRelabelerSource.contains("LiftRecoveryRelabelConfig"))
    #expect(liftRelabelerSource.contains("teacherDrives"))
    #expect(liftRelabelerSource.contains("DriveIntent(index: DriveIndex(3)"))
}

@Test func mlxDatasetLoadingIsDeterministicForHarnessMixing() throws {
    let mlxSource = try readSource("Sources/KuyuMLX/ManasMLXModelStore.swift")
    let trainingSource = try readTrainingSource("Sources/KuyuTraining/TrainingRunOrchestrator.swift")

    #expect(mlxSource.contains(".sorted { $0.lastPathComponent < $1.lastPathComponent }"))
    #expect(trainingSource.contains("sources: repeatedAdditionalDatasetURLs + [exportedDatasetDirectory]"))
}

@Test func simulationViewModelDelegatesLoopStateReduction() throws {
    let source = try readSource("Sources/KuyuUI/Model/SimulationViewModel.swift")
    let reducerSource = try readSource("Sources/KuyuUI/Services/TrainingLoopStateReducer.swift")

    #expect(source.contains("trainingLoopReducer.reduce"))
    #expect(source.contains("currentTrainingLoopState()"))
    #expect(source.contains("applyTrainingLoopState("))
    #expect(reducerSource.contains("struct TrainingLoopStateReducer"))
    #expect(reducerSource.contains("TrainingLoopStateSnapshot"))
    #expect(reducerSource.contains("case .completed"))
    #expect(!source.contains("loopStatusMessage = \"Iteration \\(iteration)\""))
}

@Test func snapshotBackendContractStaysOutsideMLXImplementation() throws {
    let contract = try readTrainingSource("Sources/KuyuTraining/TrainingBackendSnapshot.swift")
    let workerSnapshot = try readTrainingSource("Sources/KuyuTraining/WorkerSnapshot.swift")
    let workerPlan = try readTrainingSource("Sources/KuyuTraining/ParallelTrainingWorkerPlan.swift")
    let checkpointDecision = try readTrainingSource("Sources/KuyuTraining/CheckpointDecision.swift")
    let reinforcementContract = try readTrainingSource("Sources/KuyuTraining/ReinforcementTrainingBackend.swift")
    let mlxBackend = try readSource("Sources/KuyuMLX/ManasMLXTrainingBackend.swift")
    let mlxBackendFactory = try readSource("Sources/KuyuMLX/ManasMLXTrainingBackendFactory.swift")
    let mlxSnapshotProvider = try readSource("Sources/KuyuMLX/ManasMLXSnapshotProvider.swift")
    let mlxRuntime = try readSource("Sources/KuyuMLX/ManasMLXTrainingRuntime.swift")
    let loopController = try readSource("Sources/KuyuUI/Services/TrainingLoopController.swift")

    #expect(contract.contains("public protocol SnapshotTrainingBackend"))
    #expect(contract.contains("TrainingBackendSnapshot"))
    #expect(reinforcementContract.contains("public protocol ReinforcementTrainingBackend"))
    #expect(loopController.contains("case reinforcementTrainingCompleted"))
    #expect(workerSnapshot.contains("public struct WorkerSnapshot"))
    #expect(workerSnapshot.contains("public protocol SnapshotProviding"))
    #expect(workerPlan.contains("public struct ParallelTrainingWorkerPlan"))
    #expect(workerPlan.contains("rolloutShardURL"))
    #expect(reinforcementContract.contains("workerPlan: ParallelTrainingWorkerPlan?"))
    #expect(checkpointDecision.contains("public struct CheckpointDecision"))
    #expect(checkpointDecision.contains("public struct CheckpointRepository"))
    #expect(mlxBackend.contains("SnapshotTrainingBackend"))
    #expect(mlxBackend.contains("ManasMLXTrainingRuntime"))
    #expect(mlxBackend.contains("checkpointDirectory(for: request)"))
    #expect(mlxBackendFactory.contains("let workerStore = ManasMLXModelStore()"))
    #expect(mlxBackendFactory.contains("candidate-checkpoints"))
    #expect(mlxBackendFactory.contains("source-checkpoint"))
    #expect(mlxSnapshotProvider.contains("SnapshotProviding"))
    #expect(mlxSnapshotProvider.contains("workerRootURL"))
    #expect(mlxSnapshotProvider.contains("copyItem"))
    #expect(!mlxBackend.contains("modelStore: ManasMLXModelStore"))
    #expect(!mlxBackend.contains(".trainCore("))
    #expect(mlxRuntime.contains(".trainCore("))
    #expect(mlxRuntime.contains("request.sourceSnapshot"))
    #expect(mlxRuntime.contains(".loadModel("))
}

private func readSource(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}

private func readTrainingSource(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("kuyu-training", isDirectory: true)
    let url = root.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}
