import Foundation
import KuyuTraining

public struct LearningCampaignArtifactValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case invalid(LearningCampaignValidation)
    }

    public init() {}

    @discardableResult
    public func validate(
        artifactRoot: URL,
        allowFailed: Bool = false,
        allowRunning: Bool = false,
        writesValidationArtifact: Bool = true
    ) throws -> LearningCampaignValidation {
        var issues: [LearningCampaignValidationIssue] = []

        func appendIssue(_ code: String, _ detail: String) {
            issues.append(LearningCampaignValidationIssue(code: code, detail: detail))
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: artifactRoot.path) else {
            appendIssue("missing-artifact-root", artifactRoot.path)
            let validation = makeValidation(root: artifactRoot, issues: issues)
            throw ValidationError.invalid(validation)
        }

        let plan: LearningCampaignPlan? = decodeJSON(
            LearningCampaignPlan.self,
            fileName: "learning-campaign-plan.json",
            root: artifactRoot,
            issues: &issues
        )
        let environment: LearningCampaignEnvironment? = decodeJSON(
            LearningCampaignEnvironment.self,
            fileName: "learning-campaign-environment.json",
            root: artifactRoot,
            issues: &issues
        )
        let statusURL = artifactRoot.appendingPathComponent("campaign-status.json")
        let status: LearningCampaignStatus?
        if allowRunning && !fileManager.fileExists(atPath: statusURL.path) {
            status = nil
        } else {
            status = decodeJSON(
                LearningCampaignStatus.self,
                fileName: "campaign-status.json",
                root: artifactRoot,
                issues: &issues
            )
        }
        let summary: LearningCampaignSummary? = decodeJSON(
            LearningCampaignSummary.self,
            fileName: "learning-campaign-summary.json",
            root: artifactRoot,
            issues: &issues
        )
        let retentionURL = artifactRoot.appendingPathComponent("artifact-retention.json")
        let retention: LearningCampaignArtifactRetentionSummary?
        if summary != nil || fileManager.fileExists(atPath: retentionURL.path) {
            retention = decodeJSON(
                LearningCampaignArtifactRetentionSummary.self,
                fileName: "artifact-retention.json",
                root: artifactRoot,
                issues: &issues
            )
        } else {
            retention = nil
        }
        let progress = decodeJSONLines(
            LearningCampaignProgressRecord.self,
            fileName: "progress.jsonl",
            root: artifactRoot,
            issues: &issues
        )
        let resourceSampleRequired = (plan?.resourceSampleSeconds ?? 30) > 0
        let resourceSampleURL = artifactRoot.appendingPathComponent("resource-samples.jsonl")
        let resourceSamples: [LearningCampaignResourceSample]
        if resourceSampleRequired || fileManager.fileExists(atPath: resourceSampleURL.path) {
            resourceSamples = decodeJSONLines(
                LearningCampaignResourceSample.self,
                fileName: "resource-samples.jsonl",
                root: artifactRoot,
                issues: &issues
            )
        } else {
            resourceSamples = []
        }

        validate(status: status, allowFailed: allowFailed, allowRunning: allowRunning, issues: &issues)
        validate(progress: progress, allowRunning: allowRunning, issues: &issues)
        validate(resourceSamples: resourceSamples, required: resourceSampleRequired, issues: &issues)
        validate(environment: environment, issues: &issues)
        validate(plan: plan, summary: summary, root: artifactRoot, issues: &issues)
        validate(plan: plan, summary: summary, retention: retention, issues: &issues)
        validateParentTaskEvaluations(plan: plan, summary: summary, root: artifactRoot, issues: &issues)
        validateParentTaskRegressions(plan: plan, summary: summary, root: artifactRoot, issues: &issues)

        let validation = makeValidation(root: artifactRoot, issues: issues)
        if writesValidationArtifact {
            try write(validation, to: artifactRoot)
        }
        guard validation.valid else {
            throw ValidationError.invalid(validation)
        }
        return validation
    }

    private func validate(
        status: LearningCampaignStatus?,
        allowFailed: Bool,
        allowRunning: Bool,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        guard let status else { return }
        if status.status != "succeeded" && !allowFailed {
            issues.append(.init(code: "campaign-not-succeeded", detail: status.status))
        }
    }

    private func validate(
        progress: [LearningCampaignProgressRecord],
        allowRunning: Bool,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        guard !progress.isEmpty else {
            issues.append(.init(code: "empty-progress", detail: "progress.jsonl"))
            return
        }
        let hasFinishedEvent = progress.contains { $0.event == "campaign-finished" }
        if !hasFinishedEvent && !allowRunning {
            issues.append(.init(code: "missing-finished-progress-event", detail: "progress.jsonl"))
        }
    }

    private func validate(
        resourceSamples: [LearningCampaignResourceSample],
        required: Bool,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        if resourceSamples.isEmpty {
            if required {
                issues.append(.init(code: "empty-resource-samples", detail: "resource-samples.jsonl"))
            }
            return
        }
        for (index, sample) in resourceSamples.enumerated() {
            if sample.artifactRootFreeBytes < 0 {
                issues.append(.init(
                    code: "invalid-resource-free-bytes",
                    detail: "resource-samples.jsonl:\(index + 1)"
                ))
            }
        }
    }

    private func validate(
        environment: LearningCampaignEnvironment?,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        guard let environment else { return }
        if environment.repositories.isEmpty {
            issues.append(.init(
                code: "missing-repository-state",
                detail: "learning-campaign-environment.json"
            ))
        }
    }

    private func validate(
        plan: LearningCampaignPlan?,
        summary: LearningCampaignSummary?,
        root: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        guard let plan, let summary else { return }
        let planSeeds = plan.seeds
        let summarySeeds = summary.runs.map(\.seed)
        if planSeeds != summarySeeds {
            issues.append(.init(
                code: "seed-summary-mismatch",
                detail: "plan=\(planSeeds) summary=\(summarySeeds)"
            ))
        }
        if summary.seedCount != summary.runs.count {
            issues.append(.init(
                code: "seed-count-mismatch",
                detail: "seedCount=\(summary.seedCount) runs=\(summary.runs.count)"
            ))
        }
        let acceptedRunCount = summary.runs.filter(\.accepted).count
        if summary.acceptedCount != acceptedRunCount {
            issues.append(.init(
                code: "accepted-count-mismatch",
                detail: "acceptedCount=\(summary.acceptedCount) runs=\(acceptedRunCount)"
            ))
        }
        let expectedFitnessCount = plan.population * plan.generations
        for run in summary.runs {
            let evolutionRoot = root
                .appendingPathComponent("seeds", isDirectory: true)
                .appendingPathComponent("seed-\(run.seed)", isDirectory: true)
                .appendingPathComponent("evolution", isDirectory: true)
            validate(seedRun: run, plan: plan, evolutionRoot: evolutionRoot, issues: &issues)
            if expectedFitnessCount > 0, run.fitnessCount != expectedFitnessCount {
                issues.append(.init(
                    code: "fitness-count-mismatch",
                    detail: "seed=\(run.seed) expected=\(expectedFitnessCount) actual=\(run.fitnessCount)"
                ))
            }
            if run.accepted, run.acceptedCheckpointURL == nil {
                issues.append(.init(
                    code: "accepted-missing-checkpoint-url",
                    detail: "seed=\(run.seed)"
                ))
            }
        }
        if summary.finalCheckpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !checkpointComplete(URL(fileURLWithPath: summary.finalCheckpoint, isDirectory: true)) {
            issues.append(.init(
                code: "incomplete-final-checkpoint",
                detail: summary.finalCheckpoint
            ))
        }
        if let expectedFinalCheckpoint = expectedFinalCheckpointPath(
            plan: plan,
            summary: summary,
            root: root,
            issues: &issues
        ),
           normalizedCheckpointPath(summary.finalCheckpoint) != expectedFinalCheckpoint {
            issues.append(.init(
                code: "final-checkpoint-mismatch",
                detail: "expected=\(expectedFinalCheckpoint) actual=\(summary.finalCheckpoint)"
            ))
        }
    }

    private func validate(
        plan: LearningCampaignPlan?,
        summary: LearningCampaignSummary?,
        retention: LearningCampaignArtifactRetentionSummary?,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        guard let plan, let summary else { return }
        guard let retention else {
            issues.append(.init(
                code: "missing-artifact-retention",
                detail: "artifact-retention.json"
            ))
            return
        }
        if retention.mode != plan.artifactRetentionPolicy.mode {
            issues.append(.init(
                code: "artifact-retention-mode-mismatch",
                detail: "plan=\(plan.artifactRetentionPolicy.mode.rawValue) retention=\(retention.mode.rawValue)"
            ))
        }
        if summary.retention != retention {
            issues.append(.init(
                code: "artifact-retention-summary-mismatch",
                detail: "summary retention does not match artifact-retention.json"
            ))
        }
        if retention.seedCount != plan.seeds.count || retention.records.map(\.seed) != plan.seeds {
            issues.append(.init(
                code: "artifact-retention-seed-mismatch",
                detail: "plan=\(plan.seeds) retention=\(retention.records.map(\.seed))"
            ))
        }
        if plan.artifactRetentionPolicy.mode == .compact,
           retention.records.contains(where: { $0.mode != .compact }) {
            issues.append(.init(
                code: "artifact-retention-record-mode-mismatch",
                detail: "compact campaign contains non-compact retention records"
            ))
        }
    }

    private func validateParentTaskEvaluations(
        plan: LearningCampaignPlan?,
        summary: LearningCampaignSummary?,
        root: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        guard let plan, plan.verifyParentTask != false else { return }
        guard plan.task == "lift" || plan.task == "singleLift" else { return }
        if let initialCheckpoint = expectedInitialParentCheckpointPath(
            plan: plan,
            root: root,
            issues: &issues
        ) {
            validateParentTaskEvaluation(
                label: "initial-parent",
                expectedTask: plan.task,
                expectedCheckpointPath: initialCheckpoint,
                root: root,
                requiresPolicyPass: true,
                issues: &issues
            )
        } else {
            issues.append(.init(
                code: "missing-initial-parent-checkpoint",
                detail: "task=\(plan.task)"
            ))
        }
        for run in summary?.runs ?? [] where run.accepted {
            guard let acceptedCheckpoint = normalizedCheckpointPath(run.acceptedCheckpointURL) else {
                issues.append(.init(
                    code: "accepted-missing-parent-task-checkpoint",
                    detail: "seed=\(run.seed)"
                ))
                continue
            }
            validateParentTaskEvaluation(
                label: "seed-\(run.seed)-accepted",
                expectedTask: plan.task,
                expectedCheckpointPath: acceptedCheckpoint,
                root: root,
                requiresPolicyPass: true,
                issues: &issues
            )
        }
    }

    private func validateParentTaskEvaluation(
        label: String,
        expectedTask: String,
        expectedCheckpointPath: String,
        root: URL,
        requiresPolicyPass: Bool,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        let url = root
            .appendingPathComponent("checkpoint-evaluations", isDirectory: true)
            .appendingPathComponent(label, isDirectory: true)
            .appendingPathComponent("checkpoint-evaluation.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            issues.append(.init(
                code: "missing-parent-task-evaluation",
                detail: "label=\(label) file=\(url.path)"
            ))
            return
        }
        let evaluation: CheckpointEvaluationArtifact
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            evaluation = try decoder.decode(CheckpointEvaluationArtifact.self, from: Data(contentsOf: url))
        } catch {
            issues.append(.init(
                code: "invalid-parent-task-evaluation",
                detail: "label=\(label) error=\(error)"
            ))
            return
        }
        let expectedProfile: TaskEvaluationProfile
        do {
            expectedProfile = try TaskEvaluationProfile.profile(task: expectedTask)
        } catch {
            issues.append(.init(
                code: "parent-task-evaluation-profile-error",
                detail: "label=\(label) error=\(error)"
            ))
            return
        }
        do {
            try CheckpointEvaluationArtifactValidator.validate(
                evaluation,
                expectedProfile: expectedProfile,
                expectedCheckpointPath: expectedCheckpointPath,
                requiresPolicyPass: requiresPolicyPass
            )
        } catch CheckpointEvaluationArtifactValidator.ValidationError.schemaVersionMismatch(let expected, let actual) {
            issues.append(.init(
                code: "parent-task-evaluation-schema-mismatch",
                detail: "label=\(label) expected=\(expected) actual=\(actual)"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.taskMismatch(let expected, let actual) {
            issues.append(.init(
                code: "parent-task-evaluation-task-mismatch",
                detail: "label=\(label) expected=\(expected) actual=\(actual)"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.profileMismatch(let expected, let actual) {
            issues.append(.init(
                code: "parent-task-evaluation-profile-mismatch",
                detail: "label=\(label) expected=\(expected) actual=\(actual)"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.checkpointMismatch(let expected, let actual) {
            issues.append(.init(
                code: "parent-task-evaluation-checkpoint-mismatch",
                detail: "label=\(label) expected=\(expected) actual=\(actual)"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.nonFiniteMetric(let metric) {
            issues.append(.init(
                code: "parent-task-evaluation-non-finite",
                detail: "label=\(label) metric=\(metric)"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.failedPolicy(let failures) {
            issues.append(.init(
                code: "parent-task-evaluation-failed",
                detail: "label=\(label) failures=\(failures.joined(separator: ","))"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.missingTaskQuality(let task) {
            issues.append(.init(
                code: "parent-task-evaluation-missing-task-quality",
                detail: "label=\(label) task=\(task)"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.missingExpectedTaskQuality(let scenarioID, let seed) {
            issues.append(.init(
                code: "parent-task-evaluation-missing-expected-task-quality",
                detail: "label=\(label) scenario=\(scenarioID) seed=\(seed)"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.unexpectedTaskQuality(let scenarioID, let seed) {
            issues.append(.init(
                code: "parent-task-evaluation-unexpected-task-quality",
                detail: "label=\(label) scenario=\(scenarioID) seed=\(seed)"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.duplicateExpectedTaskQuality(let scenarioID, let seed) {
            issues.append(.init(
                code: "parent-task-evaluation-duplicate-expected-task-quality",
                detail: "label=\(label) scenario=\(scenarioID) seed=\(seed)"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.duplicateTaskQuality(let scenarioID, let seed) {
            issues.append(.init(
                code: "parent-task-evaluation-duplicate-task-quality",
                detail: "label=\(label) scenario=\(scenarioID) seed=\(seed)"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.qualityTaskMismatch(let expected, let actual) {
            issues.append(.init(
                code: "parent-task-evaluation-quality-task-mismatch",
                detail: "label=\(label) expected=\(expected) actual=\(actual)"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.qualityEvaluatorMismatch(let expected, let actual) {
            issues.append(.init(
                code: "parent-task-evaluation-quality-evaluator-mismatch",
                detail: "label=\(label) expected=\(expected) actual=\(actual)"
            ))
        } catch CheckpointEvaluationArtifactValidator.ValidationError.failedTaskQuality(let scenarioID, let reasons) {
            issues.append(.init(
                code: "parent-task-evaluation-quality-failed",
                detail: "label=\(label) scenario=\(scenarioID) failures=\(reasons.joined(separator: ","))"
            ))
        } catch {
            issues.append(.init(
                code: "invalid-parent-task-evaluation",
                detail: "label=\(label) error=\(error)"
            ))
        }
    }

    private func validateParentTaskRegressions(
        plan: LearningCampaignPlan?,
        summary: LearningCampaignSummary?,
        root: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        guard let plan, plan.verifyParentTask != false else { return }
        guard plan.task == "lift" || plan.task == "singleLift" else { return }
        if let initialCheckpoint = expectedInitialParentCheckpointPath(
            plan: plan,
            root: root,
            issues: &issues
        ) {
            validateParentTaskRegression(
                label: "initial-parent",
                expectedCheckpointPath: initialCheckpoint,
                root: root,
                issues: &issues
            )
        }
        for run in summary?.runs ?? [] where run.accepted {
            guard let acceptedCheckpoint = normalizedCheckpointPath(run.acceptedCheckpointURL) else { continue }
            validateParentTaskRegression(
                label: "seed-\(run.seed)-accepted",
                expectedCheckpointPath: acceptedCheckpoint,
                root: root,
                issues: &issues
            )
        }
    }

    private func validateParentTaskRegression(
        label: String,
        expectedCheckpointPath: String,
        root: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        let artifactRoot = root
            .appendingPathComponent("checkpoint-regressions", isDirectory: true)
            .appendingPathComponent(label, isDirectory: true)
        let summary: KuyuRegressionSummary
        do {
            summary = try KuyuRegressionArtifactValidator().loadAndValidate(from: artifactRoot)
        } catch KuyuRegressionArtifactValidator.ValidationError.missingFile(let fileName) {
            issues.append(.init(
                code: "missing-parent-task-regression",
                detail: "label=\(label) file=\(fileName)"
            ))
            return
        } catch {
            issues.append(.init(
                code: "invalid-parent-task-regression",
                detail: "label=\(label) error=\(error)"
            ))
            return
        }
        if normalizedCheckpointPath(summary.snapshot) != normalizedCheckpointPath(expectedCheckpointPath) {
            issues.append(.init(
                code: "parent-task-regression-checkpoint-mismatch",
                detail: "label=\(label) expected=\(expectedCheckpointPath) actual=\(summary.snapshot ?? "nil")"
            ))
        }
        if !summary.allPassed {
            issues.append(.init(
                code: "parent-task-regression-failed",
                detail: "label=\(label) reasons=\(summary.gateReport.reasons.joined(separator: ","))"
            ))
        }
    }

    private func validate(
        seedRun run: LearningCampaignSeedRunSummary,
        plan: LearningCampaignPlan,
        evolutionRoot: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        let bundle: EvolutionRunArtifactBundle
        do {
            bundle = try EvolutionRunArtifactValidator().loadAndValidate(from: evolutionRoot)
        } catch EvolutionRunArtifactValidator.ValidationError.missingFile(let fileName) {
            issues.append(.init(
                code: "missing-seed-evolution-artifact",
                detail: "seed=\(run.seed) file=\(fileName)"
            ))
            return
        } catch {
            issues.append(.init(
                code: "invalid-seed-evolution-artifact",
                detail: "seed=\(run.seed) error=\(error)"
            ))
            return
        }

        if bundle.manifest.taskID != plan.task {
            issues.append(.init(
                code: "evolution-task-mismatch",
                detail: "seed=\(run.seed) plan=\(plan.task) manifest=\(bundle.manifest.taskID)"
            ))
        }
        if bundle.manifest.populationSize != plan.population {
            issues.append(.init(
                code: "evolution-population-mismatch",
                detail: "seed=\(run.seed) plan=\(plan.population) manifest=\(bundle.manifest.populationSize)"
            ))
        }
        if bundle.manifest.generationCount != plan.generations {
            issues.append(.init(
                code: "evolution-generation-mismatch",
                detail: "seed=\(run.seed) plan=\(plan.generations) manifest=\(bundle.manifest.generationCount)"
            ))
        }
        if bundle.manifest.workerCount != plan.workers {
            issues.append(.init(
                code: "evolution-worker-mismatch",
                detail: "seed=\(run.seed) plan=\(plan.workers) manifest=\(bundle.manifest.workerCount)"
            ))
        }
        if bundle.manifest.candidateEvaluationConcurrency != plan.candidateEvaluationConcurrency {
            issues.append(.init(
                code: "evolution-candidate-concurrency-mismatch",
                detail: "seed=\(run.seed) plan=\(plan.candidateEvaluationConcurrency) manifest=\(bundle.manifest.candidateEvaluationConcurrency)"
            ))
        }
        if let terminalState = run.terminalState,
           terminalState != bundle.manifest.terminalState.rawValue {
            issues.append(.init(
                code: "evolution-terminal-state-mismatch",
                detail: "seed=\(run.seed) summary=\(terminalState) manifest=\(bundle.manifest.terminalState.rawValue)"
            ))
        }
        if run.accepted != bundle.acceptedCheckpoint.accepted {
            issues.append(.init(
                code: "accepted-decision-mismatch",
                detail: "seed=\(run.seed) summary=\(run.accepted) artifact=\(bundle.acceptedCheckpoint.accepted)"
            ))
        }
        if run.acceptedCandidateID != bundle.acceptedCheckpoint.candidateID {
            issues.append(.init(
                code: "accepted-candidate-mismatch",
                detail: "seed=\(run.seed) summary=\(run.acceptedCandidateID ?? "nil") artifact=\(bundle.acceptedCheckpoint.candidateID ?? "nil")"
            ))
        }
        if normalizedCheckpointPath(run.acceptedCheckpointURL)
            != bundle.acceptedCheckpoint.checkpointURL?.path {
            issues.append(.init(
                code: "accepted-checkpoint-url-mismatch",
                detail: "seed=\(run.seed) summary=\(run.acceptedCheckpointURL ?? "nil") artifact=\(bundle.acceptedCheckpoint.checkpointURL?.path ?? "nil")"
            ))
        }
        let derivedBest = bundle.fitness.sorted { lhs, rhs in
            if lhs.scalarFitness != rhs.scalarFitness {
                return lhs.scalarFitness > rhs.scalarFitness
            }
            if lhs.generationIndex != rhs.generationIndex {
                return lhs.generationIndex > rhs.generationIndex
            }
            return lhs.candidateID < rhs.candidateID
        }.first
        let derivedGateNearest = bundle.fitness.sorted { lhs, rhs in
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
        let derivedIncumbentCandidateID = bundle.candidates.first { $0.isIncumbent == true }?.candidateID
        let derivedIncumbent = derivedIncumbentCandidateID.flatMap { candidateID in
            bundle.fitness.first { $0.candidateID == candidateID }
        }
        let derivedDelta = zipOptional(derivedBest?.scalarFitness, derivedIncumbent?.scalarFitness).map { best, incumbent in
            best - incumbent
        }
        if run.bestCandidateID != derivedBest?.candidateID {
            issues.append(.init(
                code: "best-candidate-mismatch",
                detail: "seed=\(run.seed) summary=\(run.bestCandidateID ?? "nil") artifact=\(derivedBest?.candidateID ?? "nil")"
            ))
        }
        if !approximatelyEqual(run.bestFitness, derivedBest?.scalarFitness) {
            issues.append(.init(
                code: "best-fitness-mismatch",
                detail: "seed=\(run.seed) summary=\(stringValue(run.bestFitness)) artifact=\(stringValue(derivedBest?.scalarFitness))"
            ))
        }
        if run.incumbentCandidateID != derivedIncumbentCandidateID {
            issues.append(.init(
                code: "incumbent-candidate-mismatch",
                detail: "seed=\(run.seed) summary=\(run.incumbentCandidateID ?? "nil") artifact=\(derivedIncumbentCandidateID ?? "nil")"
            ))
        }
        if !approximatelyEqual(run.incumbentFitness, derivedIncumbent?.scalarFitness) {
            issues.append(.init(
                code: "incumbent-fitness-mismatch",
                detail: "seed=\(run.seed)"
            ))
        }
        if !approximatelyEqual(run.bestVsIncumbentDelta, derivedDelta) {
            issues.append(.init(
                code: "best-vs-incumbent-delta-mismatch",
                detail: "seed=\(run.seed)"
            ))
        }
        if !approximatelyEqual(run.bestAltitudeErrorRatio, derivedBest?.altitudeErrorRatio) {
            issues.append(.init(
                code: "best-altitude-error-ratio-mismatch",
                detail: "seed=\(run.seed)"
            ))
        }
        if run.gateNearestCandidateID != derivedGateNearest?.candidateID {
            issues.append(.init(
                code: "gate-nearest-candidate-mismatch",
                detail: "seed=\(run.seed) summary=\(run.gateNearestCandidateID ?? "nil") artifact=\(derivedGateNearest?.candidateID ?? "nil")"
            ))
        }
        if !approximatelyEqual(run.gateNearestFitness, derivedGateNearest?.scalarFitness) {
            issues.append(.init(
                code: "gate-nearest-fitness-mismatch",
                detail: "seed=\(run.seed)"
            ))
        }
        if !approximatelyEqual(run.gateNearestTaskPassRate, derivedGateNearest?.taskPassRate) {
            issues.append(.init(
                code: "gate-nearest-task-pass-rate-mismatch",
                detail: "seed=\(run.seed)"
            ))
        }
        if !approximatelyEqual(run.gateNearestHoldTimeRatio, derivedGateNearest?.holdTimeRatio) {
            issues.append(.init(
                code: "gate-nearest-hold-time-ratio-mismatch",
                detail: "seed=\(run.seed)"
            ))
        }
        if !approximatelyEqual(run.gateNearestAltitudeErrorRatio, derivedGateNearest?.altitudeErrorRatio) {
            issues.append(.init(
                code: "gate-nearest-altitude-error-ratio-mismatch",
                detail: "seed=\(run.seed)"
            ))
        }
        if !approximatelyEqual(run.gateNearestSafetyViolationRate, derivedGateNearest?.safetyViolationRate) {
            issues.append(.init(
                code: "gate-nearest-safety-violation-rate-mismatch",
                detail: "seed=\(run.seed)"
            ))
        }
        if !approximatelyEqual(run.gateNearestRewardAverage, derivedGateNearest?.rewardAverage) {
            issues.append(.init(
                code: "gate-nearest-reward-average-mismatch",
                detail: "seed=\(run.seed)"
            ))
        }
        if run.reasonCount != bundle.acceptedCheckpoint.reasons.count {
            issues.append(.init(
                code: "reason-count-mismatch",
                detail: "seed=\(run.seed) summary=\(run.reasonCount) artifact=\(bundle.acceptedCheckpoint.reasons.count)"
            ))
        }
        if run.fitnessCount != bundle.fitness.count {
            issues.append(.init(
                code: "fitness-count-mismatch",
                detail: "seed=\(run.seed) summary=\(run.fitnessCount) artifact=\(bundle.fitness.count)"
            ))
        }
        if run.evaluationTraceCount != bundle.evaluationTraces.count {
            issues.append(.init(
                code: "evaluation-trace-count-mismatch",
                detail: "seed=\(run.seed) summary=\(run.evaluationTraceCount) artifact=\(bundle.evaluationTraces.count)"
            ))
        }
        if run.accepted {
            guard let checkpointURL = bundle.acceptedCheckpoint.checkpointURL else {
                issues.append(.init(
                    code: "accepted-missing-checkpoint-url",
                    detail: "seed=\(run.seed)"
                ))
                return
            }
            if !checkpointComplete(checkpointURL) {
                issues.append(.init(
                    code: "accepted-incomplete-checkpoint",
                    detail: "seed=\(run.seed) checkpoint=\(checkpointURL.path)"
                ))
            }
        }
    }

    private func normalizedCheckpointPath(_ value: String?) -> String? {
        guard let value else { return nil }
        if let url = URL(string: value), url.isFileURL {
            return url.path
        }
        return value
    }

    private func expectedFinalCheckpointPath(
        plan: LearningCampaignPlan,
        summary: LearningCampaignSummary,
        root: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) -> String? {
        if let acceptedCheckpoint = summary.runs.reversed().first(where: \.accepted)?.acceptedCheckpointURL {
            return normalizedCheckpointPath(acceptedCheckpoint)
        }
        if let sourceCheckpoint = plan.sourceCheckpoint,
           !sourceCheckpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalizedCheckpointPath(sourceCheckpoint)
        }
        let repairSelectionURL = root.appendingPathComponent("bootstrap-repair-selection.json")
        if let repairSelection = decodeBootstrapRepairSelection(from: repairSelectionURL, issues: &issues),
           let selectedCheckpointPath = repairSelection.selectedCheckpointPath,
           !selectedCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalizedCheckpointPath(selectedCheckpointPath)
        }
        return root.appendingPathComponent("bootstrap-checkpoint", isDirectory: true).path
    }

    private func expectedInitialParentCheckpointPath(
        plan: LearningCampaignPlan,
        root: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) -> String? {
        if let sourceCheckpoint = plan.sourceCheckpoint,
           !sourceCheckpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalizedCheckpointPath(sourceCheckpoint)
        }
        let repairSelectionURL = root.appendingPathComponent("bootstrap-repair-selection.json")
        if let repairSelection = decodeBootstrapRepairSelection(from: repairSelectionURL, issues: &issues),
           let selectedCheckpointPath = repairSelection.selectedCheckpointPath,
           !selectedCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalizedCheckpointPath(selectedCheckpointPath)
        }
        return root.appendingPathComponent("bootstrap-checkpoint", isDirectory: true).path
    }

    private func decodeBootstrapRepairSelection(
        from url: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) -> BootstrapRepairSelection? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(BootstrapRepairSelection.self, from: data)
        } catch {
            issues.append(.init(
                code: "invalid-bootstrap-repair-selection",
                detail: "\(url.lastPathComponent): \(error)"
            ))
            return nil
        }
    }

    private func approximatelyEqual(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.some(let lhs), .some(let rhs)):
            if !lhs.isFinite || !rhs.isFinite {
                return false
            }
            return abs(lhs - rhs) <= 0.000_000_001
        default:
            return false
        }
    }

    private func zipOptional<A, B>(_ lhs: A?, _ rhs: B?) -> (A, B)? {
        guard let lhs, let rhs else { return nil }
        return (lhs, rhs)
    }

    private func stringValue(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(value)
    }

    private func checkpointComplete(_ url: URL) -> Bool {
        ["model.json", "core.safetensors", "reflex.safetensors"].allSatisfy { fileName in
            FileManager.default.fileExists(atPath: url.appendingPathComponent(fileName).path)
        }
    }

    private func decodeJSON<T: Decodable>(
        _ type: T.Type,
        fileName: String,
        root: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) -> T? {
        let url = root.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            issues.append(.init(code: "missing-json", detail: fileName))
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            issues.append(.init(code: "invalid-json", detail: "\(fileName): \(error)"))
            return nil
        }
    }

    private func decodeJSONLines<T: Decodable>(
        _ type: T.Type,
        fileName: String,
        root: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) -> [T] {
        let url = root.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            issues.append(.init(code: "missing-jsonl", detail: fileName))
            return []
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            var records: [T] = []
            for (index, line) in text.split(separator: "\n").enumerated() where !line.isEmpty {
                do {
                    records.append(try JSONDecoder().decode(T.self, from: Data(line.utf8)))
                } catch {
                    issues.append(.init(
                        code: "invalid-jsonl",
                        detail: "\(fileName):\(index + 1): \(error)"
                    ))
                }
            }
            return records
        } catch {
            issues.append(.init(code: "invalid-jsonl", detail: "\(fileName): \(error)"))
            return []
        }
    }

    private func makeValidation(
        root: URL,
        issues: [LearningCampaignValidationIssue]
    ) -> LearningCampaignValidation {
        LearningCampaignValidation(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            artifactRoot: root.path,
            valid: issues.isEmpty,
            issueCount: issues.count,
            issues: issues
        )
    }

    private func write(_ validation: LearningCampaignValidation, to root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validation)
        let url = root.appendingPathComponent("learning-campaign-validation.json")
        try data.write(to: url, options: .atomic)
    }
}

private struct LearningCampaignEnvironment: Decodable {
    let repositories: [LearningCampaignRepositoryState]
}

private struct LearningCampaignRepositoryState: Decodable {
    let path: String
    let head: String
    let branch: String
    let dirty: Bool
}

private struct LearningCampaignProgressRecord: Decodable {
    let event: String
}

private struct LearningCampaignResourceSample: Decodable {
    let artifactRootFreeBytes: Int64
}


private struct BootstrapRepairSelection: Decodable {
    let selectedCheckpointPath: String?
}
