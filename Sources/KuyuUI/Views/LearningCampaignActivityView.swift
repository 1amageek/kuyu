import SwiftUI
import KuyuMLXCampaignContracts
import KuyuTraining

struct LearningCampaignActivityView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                currentWork
                progressRow(label: "Evolution", fraction: progressFraction, value: progressText)
                if let reinforcement = latestReinforcementIteration {
                    progressRow(
                        label: "RR-PPO",
                        fraction: reinforcement.fractionCompleted,
                        value: "\(reinforcement.completedIterationCount)/\(reinforcement.totalIterationCount)"
                    )
                }
                if let scenario = currentScenarioProgress {
                    progressRow(
                        label: "Scenarios",
                        fraction: scenario.fractionCompleted,
                        value: "\(scenario.completedUnitCount)/\(scenario.totalUnitCount)"
                    )
                    if let controlStep = currentControlStepProgress {
                        progressRow(
                            label: "Control steps",
                            fraction: controlStep.fractionCompleted,
                            value: "\(controlStep.completedUnitCount)/\(controlStep.totalUnitCount)"
                        )
                    } else {
                        progressStatusRow(label: "Control steps", value: "finalizing scenario")
                    }
                }
                activityMetrics
            }
        } label: {
            HStack {
                Label("Live Activity", systemImage: "dot.radiowaves.left.and.right")
                Spacer()
                StatusPill(activityStatus, tone: activityTone)
            }
        }
    }

    private func progressRow(label: String, fraction: Double, value: String) -> some View {
        HStack(spacing: KuyuSpacing.xs) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            ProgressView(value: min(1, max(0, fraction)), total: 1)
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)
        }
    }

    private func progressStatusRow(label: String, value: String) -> some View {
        HStack(spacing: KuyuSpacing.xs) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var currentWork: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentAction)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            Text(currentDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activityMetrics: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            StatRow(label: "Phase", value: model.learningCampaignCurrentPhase, compact: true)
            StatRow(
                label: "Current Scope",
                value: currentScopeText,
                compact: true,
                valueLineLimit: 2
            )
            if let reinforcement = latestReinforcementIteration {
                StatRow(
                    label: "RR Horizon",
                    value: "\(reinforcement.currentHorizonSteps) / \(reinforcement.fullHorizonSteps)",
                    compact: true
                )
                StatRow(
                    label: "RR Decision",
                    value: reinforcementDecisionText(reinforcement),
                    compact: true
                )
                StatRow(
                    label: "RR Constraint",
                    value: String(
                        format: "cost %.4f / %.4f, lambda %.4f",
                        reinforcement.observedCost,
                        reinforcement.costLimit,
                        reinforcement.dualLambda
                    ),
                    compact: true,
                    valueLineLimit: 2
                )
                if let focus = reinforcement.focusScope {
                    StatRow(
                        label: "RR Reward",
                        value: String(
                            format: "%.4f -> %.4f",
                            focus.baseline.rewardAverage,
                            focus.retained.rewardAverage
                        ),
                        compact: true
                    )
                    StatRow(
                        label: "RR Failures",
                        value: "\(focus.baseline.failureCount)/\(focus.baseline.episodeCount) -> \(focus.retained.failureCount)/\(focus.retained.episodeCount)",
                        compact: true
                    )
                }
            }
            StatRow(label: "Generation", value: generationText, compact: true)
            StatRow(label: "Candidates", value: candidateText, compact: true)
            StatRow(label: "Throughput", value: throughputText, compact: true)
            StatRow(label: "Campaign ETA", value: campaignETAText, compact: true)
            StatRow(label: "Scenario ETA", value: scenarioETAText, compact: true)
            StatRow(label: "Best Fitness", value: bestFitnessText, compact: true)
            StatRow(label: "Task Pass", value: taskPassText, compact: true)
            StatRow(label: "Hold / Altitude", value: qualityText, compact: true)
            StatRow(
                label: "Accelerator",
                value: acceleratorText,
                compact: true,
                valueLineLimit: 2
            )
            StatRow(label: "Parallelism", value: parallelismText, compact: true)
        }
    }

    private var currentAction: String {
        if !model.isLearningCampaignRunning {
            if let state = model.learningCampaignState {
                return state.statusLabel == "failed" ? "Campaign failed" : "Campaign is not running"
            }
            return "No campaign is running"
        }
        if let work = activeReinforcementWorkProgress {
            let nextIteration = min(
                work.totalUnitCount,
                work.completedUnitCount + 1
            )
            return "Training RR-PPO iteration \(nextIteration)/\(work.totalUnitCount)"
        }
        if let scenario = currentScenarioProgress {
            if let scenarioID = scenario.unit.scenarioID {
                return "Running scenario \(scenarioID)"
            }
            return "Running \(scenario.unit.identifier)"
        }
        if let liveCandidate = model.learningCampaignState?.latestLiveCandidate,
           let candidateID = liveCandidate.candidateID {
            return "Evaluating candidate \(candidateID)"
        }
        if let latestCandidate = latestCandidates.first {
            return "Evaluating candidate \(latestCandidate.candidateID)"
        }
        if let progress = model.learningCampaignState?.progress,
           let seed = progress.currentSeed {
            if let generationIndex = progress.currentGenerationIndex {
                return "Processing seed \(seed), generation \(generationIndex)"
            }
            return "Processing seed \(seed)"
        }
        return "Preparing campaign artifacts"
    }

    private var currentDetail: String {
        if let issue = primaryIssue,
           let status = model.learningCampaignState?.statusLabel.lowercased(),
           status == "failed" || status == "cancelled" {
            return issue
        }
        if let work = currentControlStepProgress {
            return "\(work.completedUnitCount)/\(work.totalUnitCount) control steps"
        }
        if let work = currentScenarioProgress {
            var detail = "Finalizing scenario \(work.completedUnitCount + 1)/\(work.totalUnitCount)"
            if let populationSize = work.populationSize {
                detail += " across \(populationSize) candidates"
            }
            return detail
        }
        if let reinforcement = activeReinforcementIteration,
           let focus = reinforcement.focusScope {
            return String(
                format: "%@ h=%d reward %.4f -> %.4f, failures %d -> %d",
                focus.role.rawValue,
                focus.horizonSteps,
                focus.baseline.rewardAverage,
                focus.retained.rewardAverage,
                focus.baseline.failureCount,
                focus.retained.failureCount
            )
        }
        if let event = model.learningCampaignLatestEvent {
            return event
        }
        if let issue = primaryIssue {
            return issue
        }
        return "Waiting for the next runner event."
    }

    private var activityStatus: String {
        if model.isLearningCampaignRunning { return "running" }
        return model.learningCampaignState?.statusLabel ?? "idle"
    }

    private var activityTone: StatusPill.Tone {
        if model.isLearningCampaignRunning { return .success }
        switch model.learningCampaignState?.statusLabel.lowercased() {
        case "failed", "cancelled":
            return .warning
        case "succeeded", "completed":
            return .success
        default:
            return .neutral
        }
    }

    private var progressText: String {
        String(format: "%.1f%%", progressFraction * 100)
    }

    private var generationText: String {
        guard let state = model.learningCampaignState else { return "--" }
        return "\(state.completedGenerationCount) / \(state.plannedGenerationCount)"
    }

    private var candidateText: String {
        guard let state = model.learningCampaignState else { return "--" }
        return "\(state.liveCandidateEvaluationCount) / \(state.plannedCandidateEvaluationCount)"
    }

    private var currentScopeText: String {
        guard let progress = model.learningCampaignState?.progress else { return "--" }
        var components = [progress.lifecycleStage.rawValue]
        if model.learningCampaignState?.progress.lifecycleStage == .reinforcing,
           let reinforcement = latestReinforcementIteration {
            components.append("rr-ppo i\(reinforcement.globalIteration)")
        }
        if let seed = progress.currentSeed {
            components.append(seed)
        }
        if let generationIndex = progress.currentGenerationIndex {
            components.append("g\(generationIndex)")
        }
        if let work = currentScenarioProgress {
            if let suite = work.unit.suiteIndex {
                components.append("suite \(suite)")
            }
            if let scenarioID = work.unit.scenarioID {
                components.append(scenarioID)
            }
        }
        return components.joined(separator: " / ")
    }

    private var currentScenarioProgress: TrainingWorkProgress? {
        model.learningCampaignState?.currentScenarioProgress
    }

    private var currentControlStepProgress: TrainingWorkProgress? {
        model.learningCampaignState?.currentControlStepProgress
    }

    private var latestReinforcementIteration: LearningCampaignReinforcementIterationProgress? {
        model.learningCampaignState?.latestReinforcementIteration
    }

    private var activeReinforcementIteration: LearningCampaignReinforcementIterationProgress? {
        model.learningCampaignState?.activeReinforcementIteration
    }

    private var activeReinforcementWorkProgress: TrainingWorkProgress? {
        model.learningCampaignState?.activeReinforcementWorkProgress
    }

    private func reinforcementDecisionText(
        _ progress: LearningCampaignReinforcementIterationProgress
    ) -> String {
        guard progress.accepted else { return "parent retained" }
        return progress.materiallyImproved ? "accepted / improved" : "accepted"
    }

    private var throughputText: String {
        if let estimate = model.learningCampaignState?.progress.currentControlStepEstimate,
           let value = estimate.unitsPerSecond,
           value.isFinite {
            return String(format: "%.1f steps/s", value)
        }
        guard let value = model.learningCampaignState?.progress.estimate.candidateEvaluationsPerSecond else {
            return "collecting evidence"
        }
        return String(format: "%.2f candidates/s", value)
    }

    private var scenarioETAText: String {
        if let estimate = model.learningCampaignState?.progress.currentControlStepEstimate,
           let seconds = estimate.estimatedRemainingSeconds,
           seconds.isFinite {
            return "\(durationText(seconds)) / \(estimate.confidence.rawValue) confidence"
        }
        return currentScenarioProgress == nil ? "--" : "collecting evidence"
    }

    private var campaignETAText: String {
        guard let estimate = model.learningCampaignState?.progress.estimate,
              let seconds = estimate.estimatedRemainingSeconds,
              seconds.isFinite else {
            return "unavailable"
        }
        return "\(durationText(seconds)) / \(estimate.confidence.rawValue) confidence"
    }

    private func durationText(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainder = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainder)s"
        }
        return "\(remainder)s"
    }

    private var bestFitnessText: String {
        guard let state = model.learningCampaignState,
              let best = state.bestFitness else { return "--" }
        if let delta = state.bestFitnessDeltaFromInitial {
            return String(format: "%.3f (%+.3f)", best, delta)
        }
        return String(format: "%.3f", best)
    }

    private var taskPassText: String {
        guard let value = model.learningCampaignState?.bestTaskPassRate else { return "--" }
        return String(format: "%.0f%%", value * 100)
    }

    private var qualityText: String {
        guard let state = model.learningCampaignState else { return "--" }
        let hold = state.bestHoldTimeRatio.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
        let altitude = state.bestAltitudeErrorRatio.map { String(format: "%.2f", $0) } ?? "--"
        return "\(hold) / \(altitude)"
    }

    private var progressFraction: Double {
        if let state = model.learningCampaignState {
            return state.campaignProgressFraction
        }
        return model.learningCampaignProgressFraction
    }

    private var parallelismText: String {
        model.learningCampaignState?.actualParallelismLabel
            ?? "\(model.learningCampaignCandidateEvaluationConcurrency) requested"
    }

    private var acceleratorText: String {
        if let batch = model.learningCampaignState?.latestVectorizedBatch {
            return "\(batch.acceleratorDevice) / \(batch.executionSummary)"
        }
        guard let accelerator = model.learningCampaignState?.accelerator else {
            return "pending"
        }
        let duration = String(format: "%.1f ms", accelerator.probeDurationSeconds * 1_000)
        return "\(accelerator.acceleratorLabel) / probe \(duration)"
    }

    private var latestGenerations: [LearningCampaignGenerationState] {
        model.learningCampaignState?.latestGenerations ?? []
    }

    private var latestCandidates: [LearningCampaignCandidateState] {
        guard let state = model.learningCampaignState else { return [] }
        return state.candidates.sorted { lhs, rhs in
            if lhs.generationIndex != rhs.generationIndex {
                return lhs.generationIndex > rhs.generationIndex
            }
            let lhsFitness = lhs.scalarFitness ?? -.greatestFiniteMagnitude
            let rhsFitness = rhs.scalarFitness ?? -.greatestFiniteMagnitude
            if lhsFitness != rhsFitness {
                return lhsFitness > rhsFitness
            }
            return lhs.candidateID < rhs.candidateID
        }
    }

    private var primaryIssue: String? {
        if let reason = model.learningCampaignState?.primaryFailureReason {
            return reason
        }
        if let reason = model.lastPostRegressionGate?.primaryRejectReason {
            return reason
        }
        return model.learningCampaignError
    }

}
