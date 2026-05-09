import Foundation
import KuyuTraining

public protocol LearningCampaignEvolutionRunning: Sendable {
    func runEvolution(
        seed: String,
        parentCheckpointURL: URL,
        artifactRoot: URL,
        plan: LearningCampaignPlan
    ) async throws -> EvolutionRunArtifactBundle
}

public extension LearningCampaignEvolutionRunning {
    func runEvolution(
        seed: String,
        parentCheckpointURL: URL,
        artifactRoot: URL,
        plan: LearningCampaignPlan,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async throws -> EvolutionRunArtifactBundle {
        _ = onEvent
        return try await runEvolution(
            seed: seed,
            parentCheckpointURL: parentCheckpointURL,
            artifactRoot: artifactRoot,
            plan: plan
        )
    }
}

public protocol LearningCampaignCheckpointRegressionChecking: Sendable {
    func checkCheckpointRegression(
        label: String,
        checkpointURL: URL,
        artifactRoot: URL,
        plan: LearningCampaignPlan
    ) async throws -> KuyuRegressionSummary
}

public struct LearningCampaignOrchestratorConfig: Sendable, Equatable {
    public let plan: LearningCampaignPlan
    public let artifactRoot: URL
    public let initialParentCheckpointURL: URL
    public let allowsNonEmptyArtifactRoot: Bool

    public init(
        plan: LearningCampaignPlan,
        artifactRoot: URL,
        initialParentCheckpointURL: URL,
        allowsNonEmptyArtifactRoot: Bool = false
    ) {
        self.plan = plan
        self.artifactRoot = artifactRoot
        self.initialParentCheckpointURL = initialParentCheckpointURL
        self.allowsNonEmptyArtifactRoot = allowsNonEmptyArtifactRoot
    }
}

public enum LearningCampaignOrchestratorError: Error, Sendable, Equatable {
    case artifactRootNotEmpty(path: String)
    case parentCheckpointEvaluationRejected(label: String, checkpointPath: String)
    case parentCheckpointRegressionRejected(label: String, checkpointPath: String, reasons: [String])
    case validationRejected([LearningCampaignValidationIssue])
}

public struct LearningCampaignOrchestrator: Sendable {
    private let checkpointEvaluator: any CheckpointEvaluating
    private let evolutionRunner: any LearningCampaignEvolutionRunning
    private let checkpointRegressionChecker: (any LearningCampaignCheckpointRegressionChecking)?
    private let validator: LearningCampaignArtifactValidator
    private let artifactPruner: LearningCampaignArtifactPruner

    public init(
        checkpointEvaluator: any CheckpointEvaluating,
        evolutionRunner: any LearningCampaignEvolutionRunning,
        checkpointRegressionChecker: (any LearningCampaignCheckpointRegressionChecking)? = nil,
        validator: LearningCampaignArtifactValidator = LearningCampaignArtifactValidator(),
        artifactPruner: LearningCampaignArtifactPruner = LearningCampaignArtifactPruner()
    ) {
        self.checkpointEvaluator = checkpointEvaluator
        self.evolutionRunner = evolutionRunner
        self.checkpointRegressionChecker = checkpointRegressionChecker
        self.validator = validator
        self.artifactPruner = artifactPruner
    }

    public func run(
        config: LearningCampaignOrchestratorConfig,
        context: LearningCampaignRunContext? = nil
    ) async throws -> LearningCampaignSummary {
        let startedAt = Date()
        var currentParentCheckpointURL = config.initialParentCheckpointURL
        var runs: [LearningCampaignSeedRunSummary] = []
        var retentionRecords: [LearningCampaignArtifactRetentionRecord] = []

        try rejectNonEmptyArtifactRootIfNeeded(config)
        do {
            try await context?.checkCancellation()
            try FileManager.default.createDirectory(at: config.artifactRoot, withIntermediateDirectories: true)
            try write(config.plan, fileName: "learning-campaign-plan.json", root: config.artifactRoot)
            await context?.emit(.artifactWritten(
                name: "learning-campaign-plan.json",
                path: config.artifactRoot.appendingPathComponent("learning-campaign-plan.json").path
            ))
            try writeEnvironment(root: config.artifactRoot)
            try writeResourceSampleIfNeeded(plan: config.plan, root: config.artifactRoot)
            try appendProgress(event: "campaign-started", root: config.artifactRoot)
            await context?.advanceProgress(description: "Campaign started")

            let profile = try TaskEvaluationProfile.profile(task: config.plan.task)
            if config.plan.verifyParentTask != false {
                try await evaluateCheckpoint(
                    label: "initial-parent",
                    checkpointURL: currentParentCheckpointURL,
                    profile: profile,
                    root: config.artifactRoot,
                    requiresPolicyPass: true,
                    context: context
                )
                try await evaluateCheckpointRegression(
                    label: "initial-parent",
                    checkpointURL: currentParentCheckpointURL,
                    root: config.artifactRoot,
                    plan: config.plan,
                    context: context
                )
            }

            for seed in config.plan.seeds {
                try await context?.checkCancellation()
                await context?.emit(.seedStarted(seed: seed))
                let evolutionRoot = config.artifactRoot
                    .appendingPathComponent("seeds", isDirectory: true)
                    .appendingPathComponent("seed-\(seed)", isDirectory: true)
                    .appendingPathComponent("evolution", isDirectory: true)
                let bundle: EvolutionRunArtifactBundle
                if let context {
                    let eventBox = EvolutionEventContinuationBox()
                    let stream = AsyncStream<EvolutionRunEvent> { streamContinuation in
                        eventBox.set(streamContinuation)
                    }
                    let eventTask = Task {
                        for await event in stream {
                            await forwardEvolutionEvent(event, seed: seed, context: context)
                        }
                    }
                    do {
                        bundle = try await evolutionRunner.runEvolution(
                            seed: seed,
                            parentCheckpointURL: currentParentCheckpointURL,
                            artifactRoot: evolutionRoot,
                            plan: config.plan,
                            onEvent: { event in
                                eventBox.yield(event)
                            }
                        )
                        eventBox.finish()
                        await eventTask.value
                    } catch {
                        eventBox.finish()
                        await eventTask.value
                        throw error
                    }
                } else {
                    bundle = try await evolutionRunner.runEvolution(
                        seed: seed,
                        parentCheckpointURL: currentParentCheckpointURL,
                        artifactRoot: evolutionRoot,
                        plan: config.plan
                    )
                }
                let runSummary = makeSeedRunSummary(seed: seed, bundle: bundle)
                runs.append(runSummary)
                await context?.emit(.seedCompleted(
                    seed: seed,
                    accepted: runSummary.accepted,
                    bestCandidateID: runSummary.bestCandidateID
                ))
                await context?.advanceProgress(description: "Seed \(seed) completed")

                if bundle.acceptedCheckpoint.accepted,
                   let acceptedCheckpointURL = bundle.acceptedCheckpoint.checkpointURL {
                    try await evaluateCheckpoint(
                        label: "seed-\(seed)-accepted",
                        checkpointURL: acceptedCheckpointURL,
                        profile: profile,
                        root: config.artifactRoot,
                        requiresPolicyPass: true,
                        context: context
                    )
                    try await evaluateCheckpointRegression(
                        label: "seed-\(seed)-accepted",
                        checkpointURL: acceptedCheckpointURL,
                        root: config.artifactRoot,
                        plan: config.plan,
                        context: context
                    )
                    currentParentCheckpointURL = acceptedCheckpointURL
                }
                let retentionRecord = try artifactPruner.pruneSeedArtifacts(
                    seed: seed,
                    evolutionRoot: evolutionRoot,
                    bundle: bundle,
                    policy: config.plan.artifactRetentionPolicy
                )
                retentionRecords.append(retentionRecord)
            }
            let retentionSummary = LearningCampaignArtifactRetentionSummary(
                mode: config.plan.artifactRetentionPolicy.mode,
                records: retentionRecords
            )
            try write(retentionSummary, fileName: "artifact-retention.json", root: config.artifactRoot)
            await context?.emit(.artifactWritten(
                name: "artifact-retention.json",
                path: config.artifactRoot.appendingPathComponent("artifact-retention.json").path
            ))

            let pipelineExecution = try makeAutonomousPipelineExecutionReport(
                plan: config.plan,
                runs: runs,
                root: config.artifactRoot
            )
            let summary = LearningCampaignSummary(
                artifactRoot: config.artifactRoot.path,
                seedCount: config.plan.seeds.count,
                acceptedCount: runs.filter(\.accepted).count,
                finalCheckpoint: currentParentCheckpointURL.path,
                runs: runs,
                retention: retentionSummary,
                autonomousPipelineExecution: pipelineExecution
            )
            try write(summary, fileName: "learning-campaign-summary.json", root: config.artifactRoot)
            await context?.emit(.artifactWritten(
                name: "learning-campaign-summary.json",
                path: config.artifactRoot.appendingPathComponent("learning-campaign-summary.json").path
            ))
            try appendProgress(event: "summary-written", root: config.artifactRoot)
            try writeStatus(status: "succeeded", exitCode: 0, startedAt: startedAt, root: config.artifactRoot)
            try writeFinishedProgress(status: "succeeded", exitCode: 0, root: config.artifactRoot)
            do {
                _ = try validator.validate(artifactRoot: config.artifactRoot)
            } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
                try writeStatus(status: "failed", exitCode: 1, startedAt: startedAt, root: config.artifactRoot)
                try writeFinishedProgress(status: "failed", exitCode: 1, root: config.artifactRoot)
                try regenerateFailedValidationArtifact(root: config.artifactRoot)
                await context?.emit(.failed(reason: "validation-rejected"))
                throw LearningCampaignOrchestratorError.validationRejected(validation.issues)
            }
            await context?.finishProgress(description: "Campaign completed")
            await context?.emit(.finished(summary: summary))
            return summary
        } catch is CancellationError {
            try writeFailureArtifactsIfNeeded(
                plan: config.plan,
                currentParentCheckpointURL: currentParentCheckpointURL,
                startedRuns: runs,
                retentionRecords: retentionRecords,
                failureReason: "cancelled",
                root: config.artifactRoot
            )
            try writeStatus(status: "cancelled", exitCode: 130, startedAt: startedAt, root: config.artifactRoot)
            try writeFinishedProgress(status: "cancelled", exitCode: 130, root: config.artifactRoot)
            try regenerateFailedValidationArtifact(root: config.artifactRoot)
            await context?.emit(.cancelled)
            throw CancellationError()
        } catch let error as LearningCampaignOrchestratorError {
            if case .validationRejected = error {
                throw error
            }
            try writeFailureArtifactsIfNeeded(
                plan: config.plan,
                currentParentCheckpointURL: currentParentCheckpointURL,
                startedRuns: runs,
                retentionRecords: retentionRecords,
                failureReason: String(describing: error),
                root: config.artifactRoot
            )
            try writeStatus(status: "failed", exitCode: 1, startedAt: startedAt, root: config.artifactRoot)
            try writeFinishedProgress(status: "failed", exitCode: 1, root: config.artifactRoot)
            try regenerateFailedValidationArtifact(root: config.artifactRoot)
            await context?.emit(.failed(reason: String(describing: error)))
            throw error
        } catch {
            try writeFailureArtifactsIfNeeded(
                plan: config.plan,
                currentParentCheckpointURL: currentParentCheckpointURL,
                startedRuns: runs,
                retentionRecords: retentionRecords,
                failureReason: String(describing: error),
                root: config.artifactRoot
            )
            try writeStatus(status: "failed", exitCode: 1, startedAt: startedAt, root: config.artifactRoot)
            try writeFinishedProgress(status: "failed", exitCode: 1, root: config.artifactRoot)
            try regenerateFailedValidationArtifact(root: config.artifactRoot)
            await context?.emit(.failed(reason: String(describing: error)))
            throw error
        }
    }

    private func rejectNonEmptyArtifactRootIfNeeded(_ config: LearningCampaignOrchestratorConfig) throws {
        guard !config.allowsNonEmptyArtifactRoot else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: config.artifactRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: config.artifactRoot,
            includingPropertiesForKeys: nil,
            options: []
        )
        guard contents.isEmpty else {
            throw LearningCampaignOrchestratorError.artifactRootNotEmpty(path: config.artifactRoot.path)
        }
    }

    private func evaluateCheckpoint(
        label: String,
        checkpointURL: URL,
        profile: TaskEvaluationProfile,
        root: URL,
        requiresPolicyPass: Bool,
        context: LearningCampaignRunContext?
    ) async throws {
        try await context?.checkCancellation()
        await context?.emit(.parentEvaluationStarted(label: label, checkpointPath: checkpointURL.path))
        let artifactRoot = root
            .appendingPathComponent("checkpoint-evaluations", isDirectory: true)
            .appendingPathComponent(label, isDirectory: true)
        let artifact = try await checkpointEvaluator.evaluateCheckpoint(
            request: CheckpointEvaluationRequest(
                evaluationID: "campaign-\(label)",
                profile: profile,
                checkpointURL: checkpointURL,
                artifactRoot: artifactRoot
            )
        )
        do {
            try CheckpointEvaluationArtifactValidator.validate(
                artifact,
                expectedProfile: profile,
                expectedCheckpointPath: checkpointURL.path,
                requiresPolicyPass: requiresPolicyPass
            )
        } catch {
            throw LearningCampaignOrchestratorError.parentCheckpointEvaluationRejected(
                label: label,
                checkpointPath: checkpointURL.path
            )
        }
        await context?.emit(.parentEvaluationCompleted(label: label, checkpointPath: checkpointURL.path))
        await context?.advanceProgress(description: "\(label) checkpoint evaluated")
    }

    private func forwardEvolutionEvent(
        _ event: EvolutionRunEvent,
        seed: String,
        context: LearningCampaignRunContext
    ) async {
        switch event {
        case .generationStarted(let generationIndex):
            await context.emit(.generationStarted(seed: seed, generationIndex: generationIndex))
        case .candidateEvaluated(let fitness):
            await context.emit(.candidateEvaluated(
                seed: seed,
                generationIndex: fitness.generationIndex,
                candidateID: fitness.candidateID,
                fitness: fitness.scalarFitness
            ))
        case .generationCompleted(let record):
            await context.emit(.generationCompleted(
                seed: seed,
                generationIndex: record.generationIndex,
                bestCandidateID: record.bestCandidateID
            ))
            await context.advanceProgress(description: "Seed \(seed) generation \(record.generationIndex) completed")
        default:
            break
        }
    }

    private func evaluateCheckpointRegression(
        label: String,
        checkpointURL: URL,
        root: URL,
        plan: LearningCampaignPlan,
        context: LearningCampaignRunContext?
    ) async throws {
        guard let checkpointRegressionChecker else { return }
        try await context?.checkCancellation()
        await context?.emit(.checkpointRegressionStarted(label: label, checkpointPath: checkpointURL.path))
        let artifactRoot = root
            .appendingPathComponent("checkpoint-regressions", isDirectory: true)
            .appendingPathComponent(label, isDirectory: true)
        let summary = try await checkpointRegressionChecker.checkCheckpointRegression(
            label: label,
            checkpointURL: checkpointURL,
            artifactRoot: artifactRoot,
            plan: plan
        )
        try KuyuRegressionArtifactValidator().validate(summary)
        await context?.emit(.checkpointRegressionCompleted(
            label: label,
            accepted: summary.allPassed,
            reasons: summary.gateReport.reasons
        ))
        await context?.advanceProgress(description: "\(label) regression checked")
        guard summary.allPassed else {
            throw LearningCampaignOrchestratorError.parentCheckpointRegressionRejected(
                label: label,
                checkpointPath: checkpointURL.path,
                reasons: summary.gateReport.reasons
            )
        }
    }

    private func makeSeedRunSummary(
        seed: String,
        bundle: EvolutionRunArtifactBundle
    ) -> LearningCampaignSeedRunSummary {
        let best = bestFitness(in: bundle)
        let gateNearest = gateNearestFitness(in: bundle)
        let incumbentCandidateID = bundle.candidates.first { $0.isIncumbent == true }?.candidateID
        let incumbent = incumbentCandidateID.flatMap { candidateID in
            bundle.fitness.first { $0.candidateID == candidateID }
        }
        let bestVsIncumbentDelta: Double?
        if let bestFitness = best?.scalarFitness, let incumbentFitness = incumbent?.scalarFitness {
            bestVsIncumbentDelta = bestFitness - incumbentFitness
        } else {
            bestVsIncumbentDelta = nil
        }

        return LearningCampaignSeedRunSummary(
            seed: seed,
            terminalState: bundle.manifest.terminalState.rawValue,
            accepted: bundle.acceptedCheckpoint.accepted,
            acceptedCandidateID: bundle.acceptedCheckpoint.candidateID,
            acceptedCheckpointURL: bundle.acceptedCheckpoint.checkpointURL?.path,
            incumbentCandidateID: incumbentCandidateID,
            incumbentFitness: incumbent?.scalarFitness,
            bestCandidateID: best?.candidateID,
            bestFitness: best?.scalarFitness,
            bestVsIncumbentDelta: bestVsIncumbentDelta,
            bestTaskPassRate: best?.taskPassRate,
            bestHoldTimeRatio: best?.holdTimeRatio,
            bestAltitudeErrorRatio: best?.altitudeErrorRatio,
            bestSafetyViolationRate: best?.safetyViolationRate,
            bestRewardAverage: best?.rewardAverage,
            gateNearestCandidateID: gateNearest?.candidateID,
            gateNearestFitness: gateNearest?.scalarFitness,
            gateNearestTaskPassRate: gateNearest?.taskPassRate,
            gateNearestHoldTimeRatio: gateNearest?.holdTimeRatio,
            gateNearestAltitudeErrorRatio: gateNearest?.altitudeErrorRatio,
            gateNearestSafetyViolationRate: gateNearest?.safetyViolationRate,
            gateNearestRewardAverage: gateNearest?.rewardAverage,
            fitnessCount: bundle.fitness.count,
            reasonCount: bundle.acceptedCheckpoint.reasons.count,
            evaluationTraceCount: bundle.evaluationTraces.count,
            overlappedEvaluation: bundle.evaluationTraces.contains { $0.activeEvaluationCountAtStart > 1 }
        )
    }

    private func makeAutonomousPipelineExecutionReport(
        plan: LearningCampaignPlan,
        runs: [LearningCampaignSeedRunSummary],
        root: URL
    ) throws -> AutonomousTrainingPipelineExecutionReport? {
        guard let pipeline = plan.autonomousPipeline else { return nil }
        return AutonomousTrainingPipelineExecutionSynthesizer().makeReport(
            plan: pipeline,
            completions: try autonomousStageCompletions(
                pipeline: pipeline,
                plan: plan,
                runs: runs,
                root: root
            ),
            blocks: autonomousStageBlocks(pipeline: pipeline, runs: runs, root: root)
        )
    }

    private func autonomousStageCompletions(
        pipeline: AutonomousTrainingPipelinePlan,
        plan: LearningCampaignPlan,
        runs: [LearningCampaignSeedRunSummary],
        root: URL
    ) throws -> [AutonomousTrainingStageCompletion] {
        var completions: [AutonomousTrainingStageCompletion] = []
        if let stage = pipeline.stages.first(where: { $0.kind == .imitation }) {
            completions.append(AutonomousTrainingStageCompletion(
                stageID: stage.stageID,
                satisfiedGates: stage.requiredExitGates,
                evidence: [
                    AutonomousTrainingStageEvidence(
                        kind: .checkpointEvaluation,
                        path: root
                            .appendingPathComponent("checkpoint-evaluations", isDirectory: true)
                            .appendingPathComponent("initial-parent", isDirectory: true)
                            .appendingPathComponent("checkpoint-evaluation.json")
                            .path,
                        safetyGate: .modelBundleValidated
                    ),
                    AutonomousTrainingStageEvidence(
                        kind: .checkpointEvaluation,
                        path: root
                            .appendingPathComponent("checkpoint-evaluations", isDirectory: true)
                            .appendingPathComponent("initial-parent", isDirectory: true)
                            .appendingPathComponent("checkpoint-evaluation.json")
                            .path,
                        safetyGate: .artifactLineageComplete
                    )
                ]
            ))
        }
        if let reinforcementArtifact = plan.reinforcementTrainingArtifactDirectory,
           let stage = pipeline.stages.first(where: { $0.kind == .reinforcement }) {
            let artifactDirectory = URL(fileURLWithPath: reinforcementArtifact, isDirectory: true)
            let bundle = try TrainingRunArtifactValidator().loadAndValidate(from: artifactDirectory)
            completions.append(try AutonomousTrainingStageCompletionFactory().reinforcementCompletion(
                stage: stage,
                bundle: bundle
            ))
        }
        if runs.contains(where: \.accepted),
           let stage = pipeline.stages.first(where: { $0.kind == .evolution }),
           let acceptedCheckpointPath = runs.compactMap(\.acceptedCheckpointURL).last {
            completions.append(AutonomousTrainingStageCompletion(
                stageID: stage.stageID,
                satisfiedGates: stage.requiredExitGates,
                evidence: [
                    AutonomousTrainingStageEvidence(
                        kind: .evolutionArtifact,
                        path: root.appendingPathComponent("seeds", isDirectory: true).path,
                        safetyGate: .scenarioRegressionPassed
                    ),
                    AutonomousTrainingStageEvidence(
                        kind: .modelBundle,
                        path: acceptedCheckpointPath,
                        safetyGate: .modelBundleValidated
                    )
                ]
            ))
        }
        return completions
    }

    private func autonomousStageBlocks(
        pipeline: AutonomousTrainingPipelinePlan,
        runs: [LearningCampaignSeedRunSummary],
        root: URL
    ) -> [AutonomousTrainingStageBlock] {
        var blocks: [AutonomousTrainingStageBlock] = []
        if !runs.contains(where: \.accepted),
           let stage = pipeline.stages.first(where: { $0.kind == .evolution }) {
            blocks.append(AutonomousTrainingStageBlock(
                stageID: stage.stageID,
                failureReasons: ["no-accepted-evolution-checkpoint"],
                evidence: [
                    AutonomousTrainingStageEvidence(
                        kind: .evolutionArtifact,
                        path: root.appendingPathComponent("seeds", isDirectory: true).path
                    )
                ]
            ))
        }
        return blocks
    }

    private func bestFitness(in bundle: EvolutionRunArtifactBundle) -> FitnessSummary? {
        bundle.fitness.sorted { lhs, rhs in
            if lhs.scalarFitness != rhs.scalarFitness {
                return lhs.scalarFitness > rhs.scalarFitness
            }
            if lhs.generationIndex != rhs.generationIndex {
                return lhs.generationIndex > rhs.generationIndex
            }
            return lhs.candidateID < rhs.candidateID
        }.first
    }

    private func gateNearestFitness(in bundle: EvolutionRunArtifactBundle) -> FitnessSummary? {
        bundle.fitness.sorted { lhs, rhs in
            if lhs.taskPassRate != rhs.taskPassRate {
                return lhs.taskPassRate > rhs.taskPassRate
            }
            if (lhs.holdTimeRatio ?? 0) != (rhs.holdTimeRatio ?? 0) {
                return (lhs.holdTimeRatio ?? 0) > (rhs.holdTimeRatio ?? 0)
            }
            if (lhs.altitudeErrorRatio ?? .greatestFiniteMagnitude)
                != (rhs.altitudeErrorRatio ?? .greatestFiniteMagnitude) {
                return (lhs.altitudeErrorRatio ?? .greatestFiniteMagnitude)
                    < (rhs.altitudeErrorRatio ?? .greatestFiniteMagnitude)
            }
            if lhs.safetyViolationRate != rhs.safetyViolationRate {
                return lhs.safetyViolationRate < rhs.safetyViolationRate
            }
            if lhs.rewardAverage != rhs.rewardAverage {
                return lhs.rewardAverage > rhs.rewardAverage
            }
            if lhs.scalarFitness != rhs.scalarFitness {
                return lhs.scalarFitness > rhs.scalarFitness
            }
            if lhs.generationIndex != rhs.generationIndex {
                return lhs.generationIndex > rhs.generationIndex
            }
            return lhs.candidateID < rhs.candidateID
        }.first
    }

    private func write<T: Encodable>(_ value: T, fileName: String, root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: root.appendingPathComponent(fileName), options: [.atomic])
    }

    private func appendProgress(
        event: String,
        status: String? = nil,
        exitCode: Int? = nil,
        root: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let record = LearningCampaignProgressEvent(
            event: event,
            timestamp: Date(),
            status: status,
            exitCode: exitCode
        )
        let data = try encoder.encode(record)
        let url = root.appendingPathComponent("progress.jsonl")
        var output = FileManager.default.fileExists(atPath: url.path)
            ? try Data(contentsOf: url)
            : Data()
        output.append(data)
        output.append(Data("\n".utf8))
        try output.write(to: url, options: [.atomic])
    }

    private func writeFinishedProgress(status: String, exitCode: Int, root: URL) throws {
        let url = root.appendingPathComponent("progress.jsonl")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let records: [LearningCampaignProgressEvent]
        if FileManager.default.fileExists(atPath: url.path) {
            let raw = try String(contentsOf: url, encoding: .utf8)
            records = try raw
                .split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { line in
                    try decoder.decode(LearningCampaignProgressEvent.self, from: Data(line.utf8))
                }
                .filter { $0.event != "campaign-finished" }
        } else {
            records = []
        }
        var output = Data()
        for record in records {
            output.append(try encoder.encode(record))
            output.append(Data("\n".utf8))
        }
        let finalRecord = LearningCampaignProgressEvent(
            event: "campaign-finished",
            timestamp: Date(),
            status: status,
            exitCode: exitCode
        )
        output.append(try encoder.encode(finalRecord))
        output.append(Data("\n".utf8))
        try output.write(to: url, options: [.atomic])
    }

    private func regenerateFailedValidationArtifact(root: URL) throws {
        do {
            _ = try validator.validate(
                artifactRoot: root,
                allowFailed: true,
                writesValidationArtifact: true
            )
        } catch LearningCampaignArtifactValidator.ValidationError.invalid {
            return
        }
    }

    private func writeFailureArtifactsIfNeeded(
        plan: LearningCampaignPlan,
        currentParentCheckpointURL: URL,
        startedRuns: [LearningCampaignSeedRunSummary],
        retentionRecords: [LearningCampaignArtifactRetentionRecord],
        failureReason: String,
        root: URL
    ) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let retentionSummary = failureRetentionSummary(
            plan: plan,
            retentionRecords: retentionRecords
        )
        try write(retentionSummary, fileName: "artifact-retention.json", root: root)
        let runs = failureRuns(plan: plan, startedRuns: startedRuns)
        let summary = LearningCampaignSummary(
            artifactRoot: root.path,
            seedCount: runs.count,
            acceptedCount: runs.filter(\.accepted).count,
            finalCheckpoint: currentParentCheckpointURL.path,
            runs: runs,
            retention: retentionSummary,
            autonomousPipelineExecution: failurePipelineExecution(
                plan: plan,
                reason: failureReason,
                root: root
            )
        )
        try write(summary, fileName: "learning-campaign-summary.json", root: root)
        try write(
            LearningCampaignFailureSummary(
                artifactRoot: root.path,
                task: plan.task,
                sourceCheckpoint: plan.sourceCheckpoint,
                finalCheckpoint: currentParentCheckpointURL.path,
                reason: failureReason
            ),
            fileName: "learning-campaign-failure-summary.json",
            root: root
        )
    }

    private func failureRetentionSummary(
        plan: LearningCampaignPlan,
        retentionRecords: [LearningCampaignArtifactRetentionRecord]
    ) -> LearningCampaignArtifactRetentionSummary {
        let existingSeeds = Set(retentionRecords.map(\.seed))
        let missingRecords = plan.seeds
            .filter { !existingSeeds.contains($0) }
            .map { seed in
                LearningCampaignArtifactRetentionRecord(
                    seed: seed,
                    mode: plan.artifactRetentionPolicy.mode,
                    prunedCheckpointCount: 0,
                    prunedCandidateEvaluationArtifactCount: 0,
                    prunedByteCount: 0,
                    preservedCheckpointPaths: []
                )
            }
        return LearningCampaignArtifactRetentionSummary(
            mode: plan.artifactRetentionPolicy.mode,
            records: retentionRecords + missingRecords
        )
    }

    private func failureRuns(
        plan: LearningCampaignPlan,
        startedRuns: [LearningCampaignSeedRunSummary]
    ) -> [LearningCampaignSeedRunSummary] {
        var runsBySeed = Dictionary(uniqueKeysWithValues: startedRuns.map { ($0.seed, $0) })
        for seed in plan.seeds where runsBySeed[seed] == nil {
            runsBySeed[seed] = LearningCampaignSeedRunSummary(
                seed: seed,
                terminalState: "not-started",
                accepted: false,
                acceptedCandidateID: nil,
                acceptedCheckpointURL: nil,
                incumbentCandidateID: nil,
                incumbentFitness: nil,
                bestCandidateID: nil,
                bestFitness: nil,
                bestVsIncumbentDelta: nil,
                bestTaskPassRate: nil,
                bestHoldTimeRatio: nil,
                bestAltitudeErrorRatio: nil,
                bestSafetyViolationRate: nil,
                bestRewardAverage: nil,
                gateNearestCandidateID: nil,
                gateNearestFitness: nil,
                gateNearestTaskPassRate: nil,
                gateNearestHoldTimeRatio: nil,
                gateNearestAltitudeErrorRatio: nil,
                gateNearestSafetyViolationRate: nil,
                gateNearestRewardAverage: nil,
                fitnessCount: 0,
                reasonCount: 1,
                evaluationTraceCount: 0,
                overlappedEvaluation: false
            )
        }
        return plan.seeds.compactMap { runsBySeed[$0] }
    }

    private func failurePipelineExecution(
        plan: LearningCampaignPlan,
        reason: String,
        root: URL
    ) -> AutonomousTrainingPipelineExecutionReport? {
        guard let pipeline = plan.autonomousPipeline else { return nil }
        let firstStage = pipeline.stages.first?.stageID
        let initialEvaluationPath = root
            .appendingPathComponent("checkpoint-evaluations", isDirectory: true)
            .appendingPathComponent("initial-parent", isDirectory: true)
            .appendingPathComponent("checkpoint-evaluation.json")
            .path
        let evidence = FileManager.default.fileExists(atPath: initialEvaluationPath)
            ? [
                AutonomousTrainingStageEvidence(
                    kind: .checkpointEvaluation,
                    path: initialEvaluationPath
                )
            ]
            : []
        let blocks = firstStage.map { stageID in
            [
                AutonomousTrainingStageBlock(
                    stageID: stageID,
                    failureReasons: [reason],
                    evidence: evidence
                )
            ]
        } ?? []
        return AutonomousTrainingPipelineExecutionSynthesizer().makeReport(
            plan: pipeline,
            completions: [],
            blocks: blocks
        )
    }

    private func writeStatus(
        status: String,
        exitCode: Int,
        startedAt: Date,
        root: URL
    ) throws {
        let formatter = ISO8601DateFormatter()
        let campaignStatus = LearningCampaignStatus(
            status: status,
            exitCode: exitCode,
            startedAt: formatter.string(from: startedAt),
            finishedAt: formatter.string(from: Date())
        )
        try write(campaignStatus, fileName: "campaign-status.json", root: root)
    }

    private func writeEnvironment(root: URL) throws {
        let processEnvironment = ProcessInfo.processInfo.environment
        let repositoryPath = FileManager.default.currentDirectoryPath
        let swiftVersion = commandSnapshot("/usr/bin/xcrun", arguments: ["swift", "--version"])
        let xcodebuildVersion = commandSnapshot("/usr/bin/xcodebuild", arguments: ["-version"])
        let gitHead = commandSnapshot("/usr/bin/git", arguments: ["rev-parse", "HEAD"])
        let gitBranch = commandSnapshot("/usr/bin/git", arguments: ["rev-parse", "--abbrev-ref", "HEAD"])
        let gitStatus = commandSnapshot("/usr/bin/git", arguments: ["status", "--porcelain"])
        let environment = LearningCampaignEnvironmentSnapshot(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            host: ProcessInfo.processInfo.hostName,
            platform: "macOS",
            machine: ProcessInfo.processInfo.machineHardwareName,
            swiftVersion: swiftVersion.output,
            xcodebuildVersion: xcodebuildVersion.output,
            destination: processEnvironment["KUYU_XCODE_DESTINATION"] ?? "platform=macOS",
            configuration: processEnvironment["KUYU_XCODE_CONFIGURATION"] ?? "Debug",
            derivedData: processEnvironment["KUYU_XCODE_DERIVED_DATA"] ?? "",
            lockPath: processEnvironment["KUYU_LEARNING_LOCK_PATH"] ?? "",
            commands: [
                swiftVersion,
                xcodebuildVersion,
                gitHead,
                gitBranch,
                gitStatus,
            ],
            repositories: [
                LearningCampaignRepositorySnapshot(
                    path: repositoryPath,
                    head: gitHead.output,
                    branch: gitBranch.output,
                    dirty: !gitStatus.output.isEmpty
                ),
            ]
        )
        try write(environment, fileName: "learning-campaign-environment.json", root: root)
    }

    private func commandSnapshot(_ executablePath: String, arguments: [String]) -> LearningCampaignCommandSnapshot {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let errorOutput = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return LearningCampaignCommandSnapshot(
                executablePath: executablePath,
                arguments: arguments,
                status: process.terminationStatus == 0 ? "succeeded" : "failed",
                terminationStatus: process.terminationStatus,
                output: output,
                errorOutput: errorOutput
            )
        } catch {
            return LearningCampaignCommandSnapshot(
                executablePath: executablePath,
                arguments: arguments,
                status: "unavailable",
                terminationStatus: nil,
                output: "",
                errorOutput: String(describing: error)
            )
        }
    }

    private func writeResourceSampleIfNeeded(
        plan: LearningCampaignPlan,
        root: URL
    ) throws {
        guard (plan.resourceSampleSeconds ?? 30) > 0 else { return }
        let values = try FileManager.default.attributesOfFileSystem(forPath: root.path)
        let freeBytes = (values[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let sample = LearningCampaignResourceSnapshot(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            artifactRootFreeBytes: freeBytes,
            artifactRootUsedBytes: 0,
            loadAverage1m: 0
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(sample)
        data.append(Data("\n".utf8))
        try data.write(
            to: root.appendingPathComponent("resource-samples.jsonl"),
            options: [.atomic]
        )
    }
}

private struct LearningCampaignProgressEvent: Codable {
    let event: String
    let timestamp: Date
    let status: String?
    let exitCode: Int?
}

private struct LearningCampaignFailureSummary: Codable {
    let artifactRoot: String
    let task: String
    let sourceCheckpoint: String?
    let finalCheckpoint: String
    let reason: String
}

private struct LearningCampaignEnvironmentSnapshot: Encodable {
    let timestamp: String
    let host: String
    let platform: String
    let machine: String
    let swiftVersion: String
    let xcodebuildVersion: String
    let destination: String
    let configuration: String
    let derivedData: String
    let lockPath: String
    let commands: [LearningCampaignCommandSnapshot]
    let repositories: [LearningCampaignRepositorySnapshot]
}

private struct LearningCampaignCommandSnapshot: Encodable {
    let executablePath: String
    let arguments: [String]
    let status: String
    let terminationStatus: Int32?
    let output: String
    let errorOutput: String
}

private struct LearningCampaignRepositorySnapshot: Encodable {
    let path: String
    let head: String
    let branch: String
    let dirty: Bool
}

private struct LearningCampaignResourceSnapshot: Encodable {
    let timestamp: String
    let artifactRootFreeBytes: Int64
    let artifactRootUsedBytes: Int64
    let loadAverage1m: Double
}

private extension ProcessInfo {
    var machineHardwareName: String {
        environment["HOSTTYPE"] ?? "unknown"
    }
}
