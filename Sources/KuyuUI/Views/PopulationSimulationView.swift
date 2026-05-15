import SwiftUI

struct PopulationSimulationView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                HStack(spacing: KuyuSpacing.sm) {
                    statusMetric(label: "Seed", value: activeSeedLabel)
                    statusMetric(label: "Generation", value: generationLabel)
                    statusMetric(label: "Population", value: "\(population)")
                    statusMetric(label: "Evaluated", value: "\(evaluatedCount) / \(population)")
                    statusMetric(label: "Batch", value: batchLabel)
                    statusMetric(label: "Parallelism", value: parallelismLabel)
                    statusMetric(label: "Accelerator", value: acceleratorLabel)
                    statusMetric(label: "Execution", value: executionModeLabel)
                    statusMetric(label: "Observation", value: observationModeLabel)
                    statusMetric(label: "Best", value: formattedFitness(bestFitness))
                }

                LazyVGrid(columns: gridColumns, spacing: 5) {
                    ForEach(slots) { slot in
                        PopulationCandidateCell(slot: slot)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: KuyuSpacing.md) {
                    legendItem("Pending", color: .secondary.opacity(0.35))
                    legendItem("Evaluated", color: .purple)
                    legendItem("Task Pass", color: .green)
                    legendItem("Safety / Gate Failure", color: .red)
                    legendItem("Best", color: .cyan)
                    Spacer()
                    Text("Each square is one candidate in the active generation.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            HStack {
                Label("Population Simulation", systemImage: "circle.grid.2x2")
                Spacer()
                Text(runStateLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(runStateColor)
            }
        }
    }

    private var state: LearningCampaignRunStoreState? {
        model.learningCampaignState
    }

    private var population: Int {
        max(1, state?.plan?.population ?? model.learningCampaignPopulation)
    }

    private var activeGenerationIndex: Int {
        if let progressGeneration = model.learningCampaignProgressEventsForDisplay.last(where: {
            $0.generationIndex != nil
        })?.generationIndex {
            return progressGeneration
        }
        return state?.latestCompletedGenerationIndex ?? 0
    }

    private var activeSeed: String {
        if let seed = model.learningCampaignProgressEventsForDisplay.last(where: {
            $0.generationIndex == activeGenerationIndex && $0.seed != nil
        })?.seed {
            return seed
        }
        if let seed = state?.plan?.seeds.first {
            return seed
        }
        return "seed-1"
    }

    private var activeSeedLabel: String {
        activeSeed.replacingOccurrences(of: "seed-", with: "")
    }

    private var generationLabel: String {
        let planned = state?.plannedGenerationCount ?? model.learningCampaignGenerations
        return "\(activeGenerationIndex) / \(planned)"
    }

    private var parallelismLabel: String {
        let workers = state?.plan?.workers ?? model.learningCampaignWorkers
        let concurrency = state?.plan?.candidateEvaluationConcurrency ?? model.learningCampaignCandidateEvaluationConcurrency
        if let latest = state?.latestVectorizedBatch {
            return "\(latest.completedCandidateCount)/\(latest.candidateCount)"
        }
        return "\(concurrency) x \(workers)"
    }

    private var batchLabel: String {
        guard let latest = state?.latestVectorizedBatch else { return "--" }
        return "\(latest.kind.rawValue) g\(latest.generationIndex)"
    }

    private var acceleratorLabel: String {
        state?.latestAcceleratorDevice ?? "--"
    }

    private var executionModeLabel: String {
        guard let latest = state?.latestVectorizedBatch else { return "--" }
        switch latest.kind {
        case .variation:
            return "MLX variation"
        case .evaluation:
            if latest.worldExecutionMode?.hasPrefix("mlx-tensor-") == true {
                let action = formattedActionEncoding(latest.actionEncoding)
                if let active = latest.worldActiveActionDimension {
                    return "MLX \(action) policy + tensor world (\(active) active)"
                }
                return "MLX \(action) policy + tensor world"
            }
            return "MLX policy + CPU world"
        }
    }

    private var observationModeLabel: String {
        guard let latest = state?.latestVectorizedBatch else { return "--" }
        switch latest.observationExecutionMode {
        case "mlx-tensor-ctbr-observation-history-v1":
            return "Tensor CTBR history"
        case "mlx-tensor-ctbr-observation-bridge-v1":
            return "Tensor CTBR bridge"
        case "cpu-materialized-ctbr-observations":
            return "CPU CTBR materialized"
        case "mlx-tensor-direct-motor-observation-bridge-v1":
            return "Tensor motor bridge"
        case "cpu-materialized-direct-motor-observations":
            return "CPU motor materialized"
        case let mode?:
            return mode
        case nil:
            return "--"
        }
    }

    private func formattedActionEncoding(_ value: String?) -> String {
        switch value {
        case "ctbr":
            return "CTBR"
        case "directMotor":
            return "direct motor"
        case "jointTargets":
            return "joint targets"
        case "vehicleSteerThrottleBrake":
            return "steer/throttle/brake"
        case let value?:
            return value
        case nil:
            return "action"
        }
    }

    private var runStateLabel: String {
        state?.statusLabel ?? (model.isLearningCampaignRunning ? "running" : "ready")
    }

    private var runStateColor: Color {
        switch runStateLabel.lowercased() {
        case "running", "started":
            return .green
        case "failed", "cancelled":
            return .red
        case "succeeded", "completed":
            return .cyan
        default:
            return .secondary
        }
    }

    private var progressRecordsByCandidateID: [String: LearningCampaignProgressRecord] {
        let records = model.learningCampaignProgressEventsForDisplay.filter { record in
            record.event == "candidate-evaluated"
            && record.seed == activeSeed
            && record.generationIndex == activeGenerationIndex
            && record.candidateID != nil
        }
        var recordsByID: [String: LearningCampaignProgressRecord] = [:]
        for record in records {
            guard let candidateID = record.candidateID else { continue }
            recordsByID[candidateID] = record
        }
        return recordsByID
    }

    private var persistedCandidatesByCandidateID: [String: LearningCampaignCandidateState] {
        guard let state else { return [:] }
        let candidates = state.candidates.filter { candidate in
            candidate.seed == activeSeed && candidate.generationIndex == activeGenerationIndex
        }
        var candidatesByID: [String: LearningCampaignCandidateState] = [:]
        for candidate in candidates {
            candidatesByID[candidate.candidateID] = candidate
        }
        return candidatesByID
    }

    private var slots: [PopulationCandidateSlot] {
        let progress = progressRecordsByCandidateID
        let persisted = persistedCandidatesByCandidateID
        let bestID = bestCandidateID(progress: progress, persisted: persisted)
        return (0..<population).map { index in
            let candidateID = "g\(activeGenerationIndex)-c\(index)"
            return PopulationCandidateSlot(
                index: index,
                candidateID: candidateID,
                progress: progress[candidateID],
                persisted: persisted[candidateID],
                isBest: candidateID == bestID
            )
        }
    }

    private var evaluatedCount: Int {
        slots.filter(\.isEvaluated).count
    }

    private var bestFitness: Double? {
        slots.compactMap(\.fitness).max()
    }

    private var gridColumns: [GridItem] {
        let count = max(8, min(20, Int(ceil(sqrt(Double(population))))))
        return Array(repeating: GridItem(.flexible(minimum: 10, maximum: 22), spacing: 5), count: count)
    }

    private func bestCandidateID(
        progress: [String: LearningCampaignProgressRecord],
        persisted: [String: LearningCampaignCandidateState]
    ) -> String? {
        let progressBest = progress.max { lhs, rhs in
            (lhs.value.fitness ?? -.greatestFiniteMagnitude) < (rhs.value.fitness ?? -.greatestFiniteMagnitude)
        }
        let persistedBest = persisted.max { lhs, rhs in
            (lhs.value.scalarFitness ?? -.greatestFiniteMagnitude) < (rhs.value.scalarFitness ?? -.greatestFiniteMagnitude)
        }
        switch (progressBest, persistedBest) {
        case (.some(let lhs), .some(let rhs)):
            let lhsValue = lhs.value.fitness ?? -.greatestFiniteMagnitude
            let rhsValue = rhs.value.scalarFitness ?? -.greatestFiniteMagnitude
            return lhsValue >= rhsValue ? lhs.key : rhs.key
        case (.some(let value), .none):
            return value.key
        case (.none, .some(let value)):
            return value.key
        case (.none, .none):
            return nil
        }
    }

    @ViewBuilder
    private func statusMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formattedFitness(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return String(format: "%.3f", value)
    }
}

private struct PopulationCandidateSlot: Identifiable, Equatable {
    let index: Int
    let candidateID: String
    let progress: LearningCampaignProgressRecord?
    let persisted: LearningCampaignCandidateState?
    let isBest: Bool

    var id: String {
        candidateID
    }

    var fitness: Double? {
        progress?.fitness ?? persisted?.scalarFitness
    }

    var rewardAverage: Double? {
        progress?.rewardAverage ?? persisted?.rewardAverage
    }

    var taskPassRate: Double? {
        progress?.taskPassRate ?? persisted?.taskPassRate
    }

    var holdTimeRatio: Double? {
        progress?.holdTimeRatio ?? persisted?.holdTimeRatio
    }

    var altitudeErrorRatio: Double? {
        progress?.altitudeErrorRatio ?? persisted?.altitudeErrorRatio
    }

    var safetyViolationRate: Double? {
        progress?.safetyViolationRate
    }

    var isEvaluated: Bool {
        fitness != nil || rewardAverage != nil || taskPassRate != nil
    }

    var status: PopulationCandidateStatus {
        guard isEvaluated else { return .pending }
        if isBest { return .best }
        if let safetyViolationRate, safetyViolationRate > 0 {
            return .failed
        }
        if let taskPassRate, taskPassRate >= 1 {
            return .passed
        }
        return .evaluated
    }

    var helpText: String {
        var parts = ["\(candidateID)"]
        if let fitness {
            parts.append("fitness \(String(format: "%.3f", fitness))")
        }
        if let rewardAverage {
            parts.append("reward \(String(format: "%.3f", rewardAverage))")
        }
        if let taskPassRate {
            parts.append("pass \(String(format: "%.0f%%", taskPassRate * 100))")
        }
        if let holdTimeRatio {
            parts.append("hold \(String(format: "%.0f%%", holdTimeRatio * 100))")
        }
        if let altitudeErrorRatio {
            parts.append("altitude \(String(format: "%.2f", altitudeErrorRatio))")
        }
        return parts.joined(separator: " | ")
    }
}

private enum PopulationCandidateStatus {
    case pending
    case evaluated
    case passed
    case failed
    case best

    var color: Color {
        switch self {
        case .pending:
            return .secondary.opacity(0.35)
        case .evaluated:
            return .purple
        case .passed:
            return .green
        case .failed:
            return .red
        case .best:
            return .cyan
        }
    }
}

private struct PopulationCandidateCell: View {
    let slot: PopulationCandidateSlot

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(slot.status.color.opacity(slot.status == .pending ? 0.35 : 0.9))
            .overlay {
                if slot.isBest {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1.4)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .help(slot.helpText)
            .accessibilityLabel(slot.helpText)
    }
}
