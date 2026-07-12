import SwiftUI
import KuyuMLXCampaignContracts

struct LearningCampaignActivityView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                currentWork
                ProgressView(value: progressFraction, total: 1)
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
                StatRow(label: "Progress", value: progressText, compact: true)
                StatRow(label: "Generation", value: generationText, compact: true)
                StatRow(label: "Candidates", value: candidateText, compact: true)
                StatRow(label: "Best Fitness", value: bestFitnessText, compact: true)
                StatRow(label: "Task Pass", value: taskPassText, compact: true)
                StatRow(label: "Hold / Altitude", value: qualityText, compact: true)
                StatRow(label: "Accelerator", value: acceleratorText, compact: true)
                StatRow(label: "Parallelism", value: parallelismText, compact: true)
            }
        }

    private var currentAction: String {
        if !model.isLearningCampaignRunning {
            if let state = model.learningCampaignState {
                return state.statusLabel == "failed" ? "Campaign stopped at validation gate" : "Campaign is not running"
            }
            return "No campaign is running"
        }
        if let liveCandidate = model.learningCampaignState?.latestLiveCandidate,
           let candidateID = liveCandidate.candidateID {
            return "Evaluating candidate \(candidateID)"
        }
        if let latestCandidate = latestCandidates.first {
            return "Evaluating candidate \(latestCandidate.candidateID)"
        }
        if let latestGeneration = latestGenerations.first {
            return "Processing seed \(latestGeneration.seed), generation \(latestGeneration.generationIndex)"
        }
        return "Preparing campaign artifacts"
    }

    private var currentDetail: String {
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
