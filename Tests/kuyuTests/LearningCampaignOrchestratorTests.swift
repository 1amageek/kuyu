import Foundation
import KuyuMLX
import KuyuScenarios
import KuyuTraining
import Testing

@MainActor
@Test func learningCampaignOrchestratorRejectsFailingInitialParentRegressionBeforeEvolution() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-campaign-parent-regression-\(UUID().uuidString)", isDirectory: true)
    let parent = root
        .deletingLastPathComponent()
        .appendingPathComponent("parent-checkpoint-\(UUID().uuidString)", isDirectory: true)
    try makeCompleteCheckpoint(parent)
    let checkpointEvaluator = FakeCampaignCheckpointEvaluator(policyPassed: true)
    let regressionChecker = FakeCampaignCheckpointRegressionChecker(allPassed: false)
    let evolutionRunner = FakeCampaignEvolutionRunner(acceptedCheckpointURL: parent)
    let orchestrator = LearningCampaignOrchestrator(
        checkpointEvaluator: checkpointEvaluator,
        evolutionRunner: evolutionRunner,
        checkpointRegressionChecker: regressionChecker
    )

    do {
        _ = try await orchestrator.run(config: makeCampaignConfig(root: root, parent: parent))
        Issue.record("Expected failing initial parent regression to reject before evolution.")
    } catch LearningCampaignOrchestratorError.parentCheckpointRegressionRejected(
        let label,
        let checkpointPath,
        let reasons
    ) {
        #expect(label == "initial-parent")
        #expect(checkpointPath == parent.path)
        #expect(reasons.contains { $0.contains("task-pass-rate-below-min") })
        #expect(await evolutionRunner.callCount == 0)
        #expect(FileManager.default.fileExists(
            atPath: root
                .appendingPathComponent("checkpoint-regressions", isDirectory: true)
                .appendingPathComponent("initial-parent", isDirectory: true)
                .appendingPathComponent("kuyu-regression-summary.json")
                .path
        ))
        let status = try decodeJSON(TestCampaignStatus.self, from: root.appendingPathComponent("campaign-status.json"))
        #expect(status.status == "failed")
        #expect(status.exitCode == 1)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@MainActor
@Test func learningCampaignOrchestratorRejectsFailingInitialParentBeforeEvolution() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-campaign-orchestrator-\(UUID().uuidString)", isDirectory: true)
    let parent = root
        .deletingLastPathComponent()
        .appendingPathComponent("parent-checkpoint-\(UUID().uuidString)", isDirectory: true)
    try makeCompleteCheckpoint(parent)
    let checkpointEvaluator = FakeCampaignCheckpointEvaluator(policyPassed: true, initialPolicyPassed: false)
    let evolutionRunner = FakeCampaignEvolutionRunner(acceptedCheckpointURL: parent)
    let orchestrator = LearningCampaignOrchestrator(
        checkpointEvaluator: checkpointEvaluator,
        evolutionRunner: evolutionRunner
    )

    do {
        _ = try await orchestrator.run(config: makeCampaignConfig(root: root, parent: parent))
        Issue.record("Expected failing initial parent checkpoint to reject before evolution.")
    } catch LearningCampaignOrchestratorError.parentCheckpointEvaluationRejected(let label, let checkpointPath) {
        #expect(label == "initial-parent")
        #expect(checkpointPath == parent.path)
        #expect(await evolutionRunner.callCount == 0)
        let status = try decodeJSON(TestCampaignStatus.self, from: root.appendingPathComponent("campaign-status.json"))
        let validation = try decodeJSON(LearningCampaignValidation.self, from: root.appendingPathComponent("learning-campaign-validation.json"))
        #expect(status.status == "failed")
        #expect(status.exitCode == 1)
        #expect(!validation.valid)
        #expect(validation.issues.contains { $0.code == "parent-task-evaluation-failed" })
        #expect(!validation.issues.contains { $0.code == "missing-json" && $0.detail == "learning-campaign-summary.json" })
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("learning-campaign-summary.json").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("learning-campaign-failure-summary.json").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: root
                .appendingPathComponent("checkpoint-evaluations", isDirectory: true)
                .appendingPathComponent("initial-parent", isDirectory: true)
                .appendingPathComponent("checkpoint-evaluation.json")
                .path
        ))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@MainActor
@Test func learningCampaignOrchestratorPromotesAcceptedCheckpointAfterAcceptedEvaluationPasses() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-campaign-orchestrator-\(UUID().uuidString)", isDirectory: true)
    let parent = root
        .deletingLastPathComponent()
        .appendingPathComponent("parent-checkpoint-\(UUID().uuidString)", isDirectory: true)
    let accepted = root
        .deletingLastPathComponent()
        .appendingPathComponent("accepted-checkpoint-\(UUID().uuidString)", isDirectory: true)
    try makeCompleteCheckpoint(parent)
    try makeCompleteCheckpoint(accepted)
    let checkpointEvaluator = FakeCampaignCheckpointEvaluator(policyPassed: true)
    let evolutionRunner = FakeCampaignEvolutionRunner(acceptedCheckpointURL: accepted)
    let orchestrator = LearningCampaignOrchestrator(
        checkpointEvaluator: checkpointEvaluator,
        evolutionRunner: evolutionRunner,
        checkpointRegressionChecker: FakeCampaignCheckpointRegressionChecker(allPassed: true)
    )

    let summary = try await orchestrator.run(config: makeCampaignConfig(root: root, parent: parent))

    #expect(summary.finalCheckpoint == accepted.path)
    #expect(summary.acceptedCount == 1)
    #expect(summary.runs.first?.acceptedCheckpointURL == accepted.path)
    #expect(FileManager.default.fileExists(
        atPath: root
            .appendingPathComponent("checkpoint-evaluations", isDirectory: true)
            .appendingPathComponent("initial-parent", isDirectory: true)
            .appendingPathComponent("checkpoint-evaluation.json")
            .path
    ))
    #expect(FileManager.default.fileExists(
        atPath: root.appendingPathComponent("learning-campaign-validation.json").path
    ))
    #expect(FileManager.default.fileExists(
        atPath: root.appendingPathComponent("artifact-retention.json").path
    ))
}

@MainActor
@Test func learningCampaignOrchestratorCompletesReinforcementStageFromAcceptedTrainingArtifact() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-campaign-rl-evidence-\(UUID().uuidString)", isDirectory: true)
    let parent = root
        .deletingLastPathComponent()
        .appendingPathComponent("parent-checkpoint-\(UUID().uuidString)", isDirectory: true)
    let accepted = root
        .deletingLastPathComponent()
        .appendingPathComponent("accepted-checkpoint-\(UUID().uuidString)", isDirectory: true)
    let reinforcementArtifact = root
        .deletingLastPathComponent()
        .appendingPathComponent("accepted-rl-artifact-\(UUID().uuidString)", isDirectory: true)
    try makeCompleteCheckpoint(parent)
    try makeCompleteCheckpoint(accepted)
    try writeAcceptedRLTrainingRunArtifact(to: reinforcementArtifact, checkpoint: accepted)
    let orchestrator = LearningCampaignOrchestrator(
        checkpointEvaluator: FakeCampaignCheckpointEvaluator(policyPassed: true),
        evolutionRunner: FakeCampaignEvolutionRunner(acceptedCheckpointURL: accepted),
        checkpointRegressionChecker: FakeCampaignCheckpointRegressionChecker(allPassed: true)
    )

    let summary = try await orchestrator.run(config: makeCampaignConfig(
        root: root,
        parent: parent,
        reinforcementArtifact: reinforcementArtifact
    ))

    let reinforcementRecord = try #require(summary.autonomousPipelineExecution?.stageRecords.first {
        $0.kind == .reinforcement
    })
    #expect(reinforcementRecord.status == .completed)
    #expect(reinforcementRecord.evidence.contains {
        $0.kind == .trainingRunArtifact && $0.path == reinforcementArtifact.path
    })
    #expect(reinforcementRecord.satisfiedGates.contains(.scenarioRegressionPassed))

    let validation = try decodeJSON(
        LearningCampaignValidation.self,
        from: root.appendingPathComponent("learning-campaign-validation.json")
    )
    #expect(validation.valid)
}

@Test func learningCampaignArtifactPrunerCompactsRejectedCandidateArtifacts() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-campaign-retention-\(UUID().uuidString)", isDirectory: true)
    let evolutionRoot = root.appendingPathComponent("evolution", isDirectory: true)
    let candidateRoot = evolutionRoot.appendingPathComponent("candidates", isDirectory: true)
    let incumbent = candidateRoot.appendingPathComponent("generation-0/candidate-0", isDirectory: true)
    let accepted = candidateRoot.appendingPathComponent("generation-0/candidate-1", isDirectory: true)
    let rejected = candidateRoot.appendingPathComponent("generation-0/candidate-2", isDirectory: true)
    try makeCompleteCheckpoint(incumbent)
    try makeCompleteCheckpoint(accepted)
    try makeCompleteCheckpoint(rejected)
    let candidateEvaluations = evolutionRoot.appendingPathComponent("candidate-evaluations", isDirectory: true)
    try FileManager.default.createDirectory(at: candidateEvaluations, withIntermediateDirectories: true)
    try Data("log".utf8).write(
        to: candidateEvaluations.appendingPathComponent("candidate-log.json"),
        options: [.atomic]
    )
    try writeRetentionEvolutionArtifacts(
        evolutionRoot: evolutionRoot,
        incumbent: incumbent,
        accepted: accepted,
        rejected: rejected
    )
    let bundle = try EvolutionRunArtifactValidator().loadAndValidate(from: evolutionRoot)

    let record = try LearningCampaignArtifactPruner().pruneSeedArtifacts(
        seed: "1",
        evolutionRoot: evolutionRoot,
        bundle: bundle,
        policy: .compact
    )

    #expect(record.mode == .compact)
    #expect(record.prunedCheckpointCount == 2)
    #expect(record.prunedCandidateEvaluationArtifactCount == 1)
    #expect(record.prunedByteCount > 0)
    #expect(!FileManager.default.fileExists(atPath: incumbent.path))
    #expect(FileManager.default.fileExists(atPath: accepted.path))
    #expect(!FileManager.default.fileExists(atPath: rejected.path))
    #expect(!FileManager.default.fileExists(atPath: candidateEvaluations.path))
}

@MainActor
@Test func learningCampaignOrchestratorRejectsNonEmptyArtifactRootBeforeWritingPlan() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-campaign-non-empty-\(UUID().uuidString)", isDirectory: true)
    let parent = root
        .deletingLastPathComponent()
        .appendingPathComponent("parent-checkpoint-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("stale".utf8).write(to: root.appendingPathComponent("stale.txt"), options: [.atomic])
    try makeCompleteCheckpoint(parent)
    let orchestrator = LearningCampaignOrchestrator(
        checkpointEvaluator: FakeCampaignCheckpointEvaluator(policyPassed: true),
        evolutionRunner: FakeCampaignEvolutionRunner(acceptedCheckpointURL: parent)
    )

    do {
        _ = try await orchestrator.run(config: makeCampaignConfig(root: root, parent: parent))
        Issue.record("Expected non-empty artifact root to reject.")
    } catch LearningCampaignOrchestratorError.artifactRootNotEmpty(let path) {
        #expect(path == root.path)
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("learning-campaign-plan.json").path
        ))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@MainActor
@Test func learningCampaignOrchestratorRegeneratesFailedValidationArtifactAfterValidationReject() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-campaign-validation-reject-\(UUID().uuidString)", isDirectory: true)
    let parent = root
        .deletingLastPathComponent()
        .appendingPathComponent("parent-checkpoint-\(UUID().uuidString)", isDirectory: true)
    let accepted = root
        .deletingLastPathComponent()
        .appendingPathComponent("accepted-checkpoint-\(UUID().uuidString)", isDirectory: true)
    try makeCompleteCheckpoint(parent)
    try makeCompleteCheckpoint(accepted)
    let orchestrator = LearningCampaignOrchestrator(
        checkpointEvaluator: FakeCampaignCheckpointEvaluator(policyPassed: true),
        evolutionRunner: FakeCampaignEvolutionRunner(acceptedCheckpointURL: accepted),
        checkpointRegressionChecker: FakeCampaignCheckpointRegressionChecker(allPassed: true)
    )

    do {
        _ = try await orchestrator.run(config: makeCampaignConfig(root: root, parent: parent, population: 3))
        Issue.record("Expected validation reject.")
    } catch LearningCampaignOrchestratorError.validationRejected {
        let status = try decodeJSON(TestCampaignStatus.self, from: root.appendingPathComponent("campaign-status.json"))
        let validation = try decodeJSON(LearningCampaignValidation.self, from: root.appendingPathComponent("learning-campaign-validation.json"))
        let progress = try readProgress(root.appendingPathComponent("progress.jsonl"))
        #expect(status.status == "failed")
        #expect(status.exitCode == 1)
        #expect(progress.filter { $0.event == "campaign-finished" }.count == 1)
        #expect(progress.last?.status == "failed")
        #expect(!validation.issues.contains { $0.code == "campaign-not-succeeded" })
        #expect(validation.issues.contains { $0.code == "fitness-count-mismatch" || $0.code == "invalid-seed-evolution-artifact" })
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private func makeCampaignConfig(
    root: URL,
    parent: URL,
    population: Int = 2,
    reinforcementArtifact: URL? = nil
) -> LearningCampaignOrchestratorConfig {
    let plan = LearningCampaignPlan(
        artifactRoot: root.path,
        task: "lift",
        suites: ["6"],
        episodes: 1,
        workers: 1,
        population: population,
        generations: 1,
        eliteCount: 1,
        candidateEvaluationConcurrency: 2,
        seeds: ["1"],
        sourceCheckpoint: parent.path,
        modelDescriptor: nil,
        variation: "gaussian",
        searchStrategy: "qualityDiversity",
        mutationRate: 0.08,
        mutationNoiseScale: 0.01,
        adaptiveMutation: LearningCampaignAdaptiveMutationPlan(),
        bootstrapSuite: "6",
        bootstrapEpisodes: 1,
        bootstrapSequence: 16,
        bootstrapEpochs: 1,
        bootstrapMaxBatches: 1,
        bootstrapLearningRate: 0.001,
        bootstrapRepairAttempts: 0,
        verifyParentTask: true,
        resumeEnabled: false,
        resourceSampleSeconds: 0,
        artifactRetentionPolicy: .full,
        availableDiskBytes: 1_000_000_000,
        requiredDiskBytes: 1,
        plannedCandidateEvaluations: population,
        plannedRegressionRollouts: 1,
        plannedRegressionEpisodes: 1,
        autonomousPipeline: AutonomousTrainingPipelineFactory().defaultPlan(
            domain: .aerialDrone,
            taskProfileIDs: ["lift-v1"]
        ),
        reinforcementTrainingArtifactDirectory: reinforcementArtifact?.path
    )
    return LearningCampaignOrchestratorConfig(
        plan: plan,
        artifactRoot: root,
        initialParentCheckpointURL: parent
    )
}

private struct TestCampaignStatus: Decodable {
    let status: String
    let exitCode: Int
}

private struct TestProgressRecord: Decodable {
    let event: String
    let status: String?
}

private func decodeJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}

private func readProgress(_ url: URL) throws -> [TestProgressRecord] {
    let raw = try String(contentsOf: url, encoding: .utf8)
    return try raw
        .split(separator: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .map { line in
            try JSONDecoder().decode(TestProgressRecord.self, from: Data(line.utf8))
        }
}

private func makeCompleteCheckpoint(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: url.appendingPathComponent("model.json"), options: [.atomic])
    try Data("core".utf8).write(to: url.appendingPathComponent("core.safetensors"), options: [.atomic])
    try Data("reflex".utf8).write(to: url.appendingPathComponent("reflex.safetensors"), options: [.atomic])
    try Data(SelfContainedBundleManifest.fixtureJSON.utf8).write(
        to: url.appendingPathComponent("manas-bundle.json"),
        options: [.atomic]
    )
}

private enum SelfContainedBundleManifest {
    static let fixtureJSON = """
    {
      "bundleID" : "fixture",
      "components" : [
        {
          "contentType" : "application/json",
          "path" : "model.json",
          "required" : true,
          "role" : "modelConfig"
        },
        {
          "contentType" : "application/vnd.safetensors",
          "path" : "core.safetensors",
          "required" : true,
          "role" : "coreWeights"
        },
        {
          "contentType" : "application/vnd.safetensors",
          "path" : "reflex.safetensors",
          "required" : true,
          "role" : "reflexWeights"
        }
      ],
      "createdAt" : "1970-01-01T00:00:00Z",
      "modelFamily" : "manas",
      "runtimeContract" : {
        "configHash" : "config",
        "descriptorHash" : "descriptor",
        "driveSemanticsID" : "drive",
        "observationSchemaID" : "observation"
      },
      "schemaVersion" : 1
    }
    """
}

private func writeAcceptedRLTrainingRunArtifact(to artifactRoot: URL, checkpoint: URL) throws {
    let runID = "accepted-rl-run"
    let startedAt = Date(timeIntervalSince1970: 1)
    let completedAt = Date(timeIntervalSince1970: 2)
    let manifest = LearningRunManifest(
        runID: runID,
        mode: .rlRollout,
        configHash: "rl-config",
        suiteID: "lift-v1",
        seedSet: [1],
        policyID: "manasMLX",
        parentCheckpointID: "parent",
        outputCheckpointID: "accepted",
        workerCount: 1,
        startedAt: startedAt,
        completedAt: completedAt,
        terminalState: .completed
    )
    let metrics = [
        TrainingMetricRecord(
            runID: runID,
            iteration: 0,
            kind: .rewardAverage,
            value: 1,
            timestamp: completedAt
        ),
        TrainingMetricRecord(
            runID: runID,
            iteration: 0,
            kind: .passRate,
            value: 1,
            timestamp: completedAt
        ),
    ]
    let convergence = ConvergenceSummary(
        runID: runID,
        accepted: true,
        reason: "accepted",
        bestCheckpointID: "accepted",
        rewardMovingAverage: 1,
        passRate: 1,
        failureRate: 0,
        safetyRegressionDetected: false,
        plateauDetected: false,
        overfitRiskDetected: false
    )
    let decision = CheckpointDecision(
        runID: runID,
        state: .accepted,
        reason: "accepted",
        candidateCheckpointID: "accepted",
        candidateCheckpointURL: checkpoint,
        publishedCheckpointURL: checkpoint,
        decidedAt: completedAt
    )
    try TrainingArtifactWriter().write(
        manifest: manifest,
        metrics: metrics,
        convergence: convergence,
        checkpointDecision: decision,
        to: artifactRoot
    )
}

private func writeRetentionEvolutionArtifacts(
    evolutionRoot: URL,
    incumbent: URL,
    accepted: URL,
    rejected: URL
) throws {
    let runID = "retention-run"
    let startedAt = Date(timeIntervalSince1970: 1)
    let completedAt = Date(timeIntervalSince1970: 2)
    let manifest = EvolutionRunManifest(
        runID: runID,
        taskID: "lift",
        configHash: "retention",
        policyID: "manasMLX",
        populationSize: 3,
        generationCount: 1,
        eliteCount: 1,
        workerCount: 1,
        candidateEvaluationConcurrency: 1,
        searchStrategy: .qualityDiversity,
        bootstrapSource: .checkpoint,
        commonRandomSeed: 1,
        mutationRate: 0.08,
        mutationNoiseScale: 0.01,
        startedAt: startedAt,
        completedAt: completedAt,
        terminalState: .completed
    )
    let candidates = [
        GenomeCandidate(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-0",
            genomeID: "genome-0",
            checkpointID: "candidate-0",
            checkpointURL: incumbent,
            mutationRate: 0,
            mutationNoiseScale: 0,
            isIncumbent: true
        ),
        GenomeCandidate(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-1",
            genomeID: "genome-1",
            parentCandidateIDs: ["candidate-0"],
            checkpointID: "candidate-1",
            checkpointURL: accepted,
            mutationRate: 0.08,
            mutationNoiseScale: 0.01
        ),
        GenomeCandidate(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-2",
            genomeID: "genome-2",
            parentCandidateIDs: ["candidate-0"],
            checkpointID: "candidate-2",
            checkpointURL: rejected,
            mutationRate: 0.08,
            mutationNoiseScale: 0.01
        ),
    ]
    let fitness = [
        FitnessSummary(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-0",
            taskID: "lift",
            scalarFitness: 1,
            rewardAverage: 1,
            taskPassRate: 1,
            safetyViolationRate: 0
        ),
        FitnessSummary(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-1",
            taskID: "lift",
            scalarFitness: 2,
            rewardAverage: 2,
            taskPassRate: 1,
            safetyViolationRate: 0
        ),
        FitnessSummary(
            runID: runID,
            generationIndex: 0,
            candidateID: "candidate-2",
            taskID: "lift",
            scalarFitness: 0,
            rewardAverage: 0,
            taskPassRate: 1,
            safetyViolationRate: 0
        ),
    ]
    try EvolutionArtifactWriter().write(
        manifest: manifest,
        generations: [
            PopulationGenerationRecord(
                runID: runID,
                generationIndex: 0,
                candidateCount: 3,
                evaluatedCandidateCount: 3,
                eliteCandidateIDs: ["candidate-1"],
                bestCandidateID: "candidate-1",
                bestFitness: 2,
                incumbentCandidateID: "candidate-0",
                incumbentFitness: 1,
                bestVsIncumbentDelta: 1,
                qualityDiversityCellCount: 1,
                mutationRate: 0.08,
                mutationNoiseScale: 0.01,
                accepted: true,
                rejectionReasons: [],
                createdAt: completedAt
            ),
        ],
        candidates: candidates,
        fitness: fitness,
        eliteArchive: EvolutionEliteArchive(
            runID: runID,
            eliteCandidateIDs: ["candidate-1"],
            bestCandidateID: "candidate-1",
            bestFitness: 2
        ),
        qualityDiversityArchive: EvolutionQualityDiversityArchive(
            runID: runID,
            descriptorKeys: ["rank"],
            cells: [
                EvolutionQualityDiversityCell(
                    cellID: "rank-1",
                    candidateID: "candidate-1",
                    generationIndex: 0,
                    fitness: 2,
                    behaviorDescriptor: ["rank": 1]
                ),
            ]
        ),
        lineage: candidates.map {
            EvolutionLineageRecord(
                runID: runID,
                generationIndex: $0.generationIndex,
                candidateID: $0.candidateID,
                genomeID: $0.genomeID,
                parentCandidateIDs: $0.parentCandidateIDs
            )
        },
        evaluationTraces: candidates.map {
            EvolutionCandidateEvaluationTrace(
                runID: runID,
                generationIndex: $0.generationIndex,
                candidateID: $0.candidateID,
                requestedConcurrency: 1,
                activeEvaluationCountAtStart: 1,
                startedAt: startedAt,
                completedAt: completedAt
            )
        },
        to: evolutionRoot
    )
}

@MainActor
private final class FakeCampaignCheckpointEvaluator: CheckpointEvaluating {
    private let policyPassed: Bool
    private let initialPolicyPassed: Bool?

    init(policyPassed: Bool, initialPolicyPassed: Bool? = nil) {
        self.policyPassed = policyPassed
        self.initialPolicyPassed = initialPolicyPassed
    }

    func evaluateCheckpoint(request: CheckpointEvaluationRequest) async throws -> CheckpointEvaluationArtifact {
        let effectivePolicyPassed = request.evaluationID.contains("initial-parent")
            ? (initialPolicyPassed ?? policyPassed)
            : policyPassed
        let quality = makeCampaignTaskQuality(task: request.profile.task)
        let artifact = CheckpointEvaluationArtifact(
            schemaVersion: CheckpointEvaluationArtifact.currentSchemaVersion,
            evaluationID: request.evaluationID,
            startedAt: Date(timeIntervalSince1970: 1),
            task: request.profile.task,
            profileID: request.profile.profileID,
            checkpointPath: request.checkpointURL.path,
            teacherScore: 1,
            policyScore: effectivePolicyPassed ? 1 : 0,
            teacherPassed: true,
            policyPassed: effectivePolicyPassed,
            failureReasons: effectivePolicyPassed ? [] : ["policy-failed"],
            expectedQualityKeys: [CheckpointEvaluationScenarioKey(qualitySummary: quality)],
            qualitySummary: [quality],
            motorMAE: 0,
            driveMAE: 0,
            finalAltitudeDelta: 0,
            policyAverageMotorFinalOutputByIndex: [0, 0, 0, 0],
            teacherAverageMotorFinalOutputByIndex: [0, 0, 0, 0],
            diagnostics: CheckpointEvaluationDiagnostics(scenarioComparisons: [
                CheckpointEvaluationScenarioDiagnostics(
                    key: CheckpointEvaluationScenarioKey(qualitySummary: quality),
                    teacherLog: nil,
                    policyLog: nil,
                    altitudeDivergenceThreshold: 0.25
                )
            ])
        )
        try FileManager.default.createDirectory(at: request.artifactRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(artifact).write(
            to: request.artifactRoot.appendingPathComponent(CheckpointEvaluationArtifact.fileName),
            options: [.atomic]
        )
        return artifact
    }
}

private actor FakeCampaignEvolutionRunner: LearningCampaignEvolutionRunning {
    private(set) var callCount = 0
    private let acceptedCheckpointURL: URL

    init(acceptedCheckpointURL: URL) {
        self.acceptedCheckpointURL = acceptedCheckpointURL
    }

    func runEvolution(
        seed: String,
        parentCheckpointURL: URL,
        artifactRoot: URL,
        plan: LearningCampaignPlan
    ) async throws -> EvolutionRunArtifactBundle {
        callCount += 1
        let runID = "campaign-seed-\(seed)"
        let startedAt = Date(timeIntervalSince1970: 1)
        let completedAt = Date(timeIntervalSince1970: 2)
        let manifest = EvolutionRunManifest(
            runID: runID,
            taskID: plan.task,
            configHash: "config",
            policyID: "manasMLX",
            populationSize: plan.population,
            generationCount: plan.generations,
            eliteCount: plan.eliteCount,
            workerCount: plan.workers,
            candidateEvaluationConcurrency: plan.candidateEvaluationConcurrency,
            searchStrategy: .qualityDiversity,
            bootstrapSource: .checkpoint,
            commonRandomSeed: 1,
            mutationRate: plan.mutationRate,
            mutationNoiseScale: plan.mutationNoiseScale,
            startedAt: startedAt,
            completedAt: completedAt,
            terminalState: .completed
        )
        let candidates = [
            GenomeCandidate(
                runID: runID,
                generationIndex: 0,
                candidateID: "candidate-0",
                genomeID: "genome-0",
                checkpointID: "parent",
                checkpointURL: parentCheckpointURL,
                mutationRate: 0,
                mutationNoiseScale: 0,
                isIncumbent: true
            ),
            GenomeCandidate(
                runID: runID,
                generationIndex: 0,
                candidateID: "candidate-1",
                genomeID: "genome-1",
                parentCandidateIDs: ["candidate-0"],
                checkpointID: "accepted",
                checkpointURL: acceptedCheckpointURL,
                mutationRate: plan.mutationRate,
                mutationNoiseScale: plan.mutationNoiseScale
            ),
        ]
        let fitness = [
            FitnessSummary(
                runID: runID,
                generationIndex: 0,
                candidateID: "candidate-0",
                taskID: plan.task,
                scalarFitness: 1,
                rewardAverage: 1,
                taskPassRate: 1,
                safetyViolationRate: 0,
                holdTimeRatio: 1,
                altitudeErrorRatio: 0,
                workerThroughput: 1
            ),
            FitnessSummary(
                runID: runID,
                generationIndex: 0,
                candidateID: "candidate-1",
                taskID: plan.task,
                scalarFitness: 2,
                rewardAverage: 2,
                taskPassRate: 1,
                safetyViolationRate: 0,
                holdTimeRatio: 1,
                altitudeErrorRatio: 0,
                workerThroughput: 1
            ),
        ]
        let generation = PopulationGenerationRecord(
            runID: runID,
            generationIndex: 0,
            candidateCount: 2,
            evaluatedCandidateCount: 2,
            eliteCandidateIDs: ["candidate-1"],
            bestCandidateID: "candidate-1",
            bestFitness: 2,
            incumbentCandidateID: "candidate-0",
            incumbentFitness: 1,
            bestVsIncumbentDelta: 1,
            qualityDiversityCellCount: 1,
            mutationRate: plan.mutationRate,
            mutationNoiseScale: plan.mutationNoiseScale,
            accepted: true,
            rejectionReasons: [],
            createdAt: completedAt
        )
        try EvolutionArtifactWriter().write(
            manifest: manifest,
            generations: [generation],
            candidates: candidates,
            fitness: fitness,
            eliteArchive: EvolutionEliteArchive(
                runID: runID,
                eliteCandidateIDs: ["candidate-1"],
                bestCandidateID: "candidate-1",
                bestFitness: 2
            ),
            qualityDiversityArchive: EvolutionQualityDiversityArchive(
                runID: runID,
                descriptorKeys: ["rank"],
                cells: [
                    EvolutionQualityDiversityCell(
                        cellID: "rank-1",
                        candidateID: "candidate-1",
                        generationIndex: 0,
                        fitness: 2,
                        behaviorDescriptor: ["rank": 1]
                    ),
                ]
            ),
            lineage: [
                EvolutionLineageRecord(
                    runID: runID,
                    generationIndex: 0,
                    candidateID: "candidate-0",
                    genomeID: "genome-0",
                    parentCandidateIDs: []
                ),
                EvolutionLineageRecord(
                    runID: runID,
                    generationIndex: 0,
                    candidateID: "candidate-1",
                    genomeID: "genome-1",
                    parentCandidateIDs: ["candidate-0"]
                ),
            ],
            evaluationTraces: [
                EvolutionCandidateEvaluationTrace(
                    runID: runID,
                    generationIndex: 0,
                    candidateID: "candidate-0",
                    requestedConcurrency: plan.candidateEvaluationConcurrency,
                    activeEvaluationCountAtStart: 1,
                    startedAt: startedAt,
                    completedAt: completedAt
                ),
                EvolutionCandidateEvaluationTrace(
                    runID: runID,
                    generationIndex: 0,
                    candidateID: "candidate-1",
                    requestedConcurrency: plan.candidateEvaluationConcurrency,
                    activeEvaluationCountAtStart: 2,
                    startedAt: startedAt,
                    completedAt: completedAt
                ),
            ],
            to: artifactRoot
        )
        return try EvolutionRunArtifactValidator().loadAndValidate(from: artifactRoot)
    }
}

private struct FakeCampaignCheckpointRegressionChecker: LearningCampaignCheckpointRegressionChecking {
    let allPassed: Bool

    func checkCheckpointRegression(
        label: String,
        checkpointURL: URL,
        artifactRoot: URL,
        plan: LearningCampaignPlan
    ) async throws -> KuyuRegressionSummary {
        let quality = ReferenceQuadrotorTaskQualitySummary(
            task: plan.task,
            scenarioID: "\(plan.task)-regression",
            seed: 1,
            passed: allPassed,
            failureReasons: allPassed ? [] : ["task-pass-rate-below-min"],
            evaluatorID: "ReferenceQuadrotorTaskQualityEvaluator",
            targetZ: 1,
            tolerance: 0.1,
            warmupTime: 0,
            requiredHoldTime: 1,
            achievedHoldTime: allPassed ? 1 : 0,
            maxAltitudeErrorAfterWarmup: allPassed ? 0 : 1,
            maxVerticalVelocityAfterWarmup: 0
        )
        let entry = KuyuRegressionRolloutEntry(
            suite: 6,
            track: "longHorizonTask",
            policyID: "manasMLX-regression",
            episodeCount: 1,
            rewardSum: allPassed ? 1 : -1,
            rewardAverage: allPassed ? 1 : -1,
            doneCount: allPassed ? 1 : 0,
            truncatedCount: 0,
            failureCount: allPassed ? 0 : 1,
            cancelledCount: 0,
            failureReasons: allPassed ? [] : ["task-pass-rate-below-min"],
            taskPassCount: allPassed ? 1 : 0,
            taskFailureCount: allPassed ? 0 : 1,
            taskFailureReasons: allPassed ? [] : ["task-pass-rate-below-min"],
            taskQuality: [quality],
            workerSummaries: [
                KuyuRegressionWorkerSummary(
                    workerIndex: 0,
                    snapshotID: checkpointURL.lastPathComponent,
                    rolloutShardPath: nil,
                    episodeCount: 1,
                    rewardSum: allPassed ? 1 : -1,
                    rewardAverage: allPassed ? 1 : -1,
                    throughput: 1,
                    doneCount: allPassed ? 1 : 0,
                    truncatedCount: 0,
                    failureCount: allPassed ? 0 : 1,
                    cancelledCount: 0
                ),
            ],
            artifactPath: nil
        )
        let gateReport = KuyuRegressionGatePolicy.report(
            preflightFailure: nil,
            environmentTasks: [],
            rolloutSuites: [entry],
            failOnTruncation: false,
            minimumRewardAverage: nil,
            qualityGateTask: plan.task
        )
        let summary = KuyuRegressionSummary(
            artifactRoot: artifactRoot.path,
            startedAt: Date(timeIntervalSince1970: 1),
            controller: "manasMLX",
            environmentController: "teacherBaseline",
            snapshot: checkpointURL.path,
            preflightPassed: true,
            preflightFailure: nil,
            environmentReady: true,
            environmentTasks: [],
            rolloutPassed: allPassed,
            rolloutSuites: [entry],
            gateReport: gateReport,
            allPassed: gateReport.accepted
        )
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(summary).write(
            to: artifactRoot.appendingPathComponent("kuyu-regression-summary.json"),
            options: [.atomic]
        )
        return summary
    }
}

private func makeCampaignTaskQuality(task: String) -> ReferenceQuadrotorTaskQualitySummary {
    ReferenceQuadrotorTaskQualitySummary(
        task: task,
        scenarioID: "\(task)-campaign",
        seed: 1,
        passed: true,
        failureReasons: [],
        evaluatorID: "ReferenceQuadrotorTaskQualityEvaluator",
        targetZ: 1,
        tolerance: 0.1,
        warmupTime: 0,
        requiredHoldTime: 1,
        achievedHoldTime: 1,
        maxAltitudeErrorAfterWarmup: 0,
        maxVerticalVelocityAfterWarmup: 0
    )
}
