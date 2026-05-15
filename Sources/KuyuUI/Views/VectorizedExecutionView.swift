import Charts
import SwiftUI

struct VectorizedExecutionView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            if batches.isEmpty && latestLiveRecord == nil {
                ContentUnavailableView(
                    "No vectorized execution artifacts yet",
                    systemImage: "square.stack.3d.up",
                    description: Text("Start a learning campaign to inspect GPU variation batches, tensor-world evaluations, live candidate batches, throughput, and execution contracts.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    HStack(alignment: .top, spacing: KuyuSpacing.md) {
                        currentBatchSummary
                        throughputChart
                    }

                    batchHistory
                }
            }
        } label: {
            HStack {
                Label("Vectorized Execution", systemImage: "square.stack.3d.up")
                Spacer()
                StatusPill(executionStatusLabel, tone: executionStatusTone)
            }
        }
    }

    private var state: LearningCampaignRunStoreState? {
        model.learningCampaignState
    }

    private var batches: [LearningCampaignVectorizedBatchState] {
        state?.vectorizedBatches ?? []
    }

    private var latestBatch: LearningCampaignVectorizedBatchState? {
        state?.latestVectorizedBatch ?? batches.last
    }

    private var latestLiveRecord: LearningCampaignProgressRecord? {
        state?.progressEvents.last { record in
            record.event == "candidate-evaluated" &&
            (
                record.gpuAcceleration != nil ||
                record.tensorWorldBatch != nil ||
                record.tensorSummary != nil ||
                record.vectorizedPopulationSize != nil
            )
        }
    }

    private var evaluationBatches: [LearningCampaignVectorizedBatchState] {
        batches.filter { $0.kind == .evaluation }
    }

    private var variationBatches: [LearningCampaignVectorizedBatchState] {
        batches.filter { $0.kind == .variation }
    }

    private var executionStatusLabel: String {
        if latestLiveRecord?.tensorSummary == true {
            return "tensor"
        }
        if latestLiveRecord?.tensorWorldBatch == true {
            return "tensor"
        }
        if latestLiveRecord?.gpuAcceleration == true {
            return "mlx"
        }
        guard let latestBatch else { return "pending" }
        if latestBatch.worldExecutionMode?.hasPrefix("mlx-tensor-") == true {
            return "tensor"
        }
        if latestBatch.kind == .variation {
            return "mlx"
        }
        return "materialized"
    }

    private var executionStatusTone: StatusPill.Tone {
        switch executionStatusLabel {
        case "tensor":
            return .success
        case "mlx":
            return .info
        case "materialized":
            return .warning
        default:
            return .neutral
        }
    }

    private var currentBatchSummary: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            Text("Current Batch")
                .font(.callout.weight(.semibold))

            if let live = latestLiveRecord {
                StatRow(label: "Kind", value: "live evaluation", compact: true)
                StatRow(label: "Seed", value: live.seed ?? "--", compact: true)
                StatRow(label: "Generation", value: live.generationIndex.map { "g\($0)" } ?? "--", compact: true)
                StatRow(label: "Candidate", value: live.candidateID ?? "--", compact: true)
                StatRow(label: "Population", value: live.vectorizedPopulationSize.map(String.init) ?? "--", compact: true)
                StatRow(label: "Worlds", value: live.vectorizedWorldCount.map(String.init) ?? "--", compact: true)
                StatRow(label: "Throughput", value: formattedThroughput(live.workerThroughput), compact: true)
                StatRow(label: "Accelerator", value: live.gpuAcceleration == true ? acceleratorName : "--", compact: true)
                StatRow(label: "Summary", value: live.tensorSummary == true ? "tensor" : "materialized", compact: true)
                StatRow(label: "World", value: live.tensorWorldBatch == true ? "MLX tensor world" : "materialized world", compact: true)
                StatRow(label: "Shape", value: liveShapeLabel(live), compact: true)
            } else if let latestBatch {
                StatRow(label: "Kind", value: latestBatch.kind.rawValue, compact: true)
                StatRow(label: "Generation", value: "g\(latestBatch.generationIndex)", compact: true)
                StatRow(label: "Population", value: "\(latestBatch.completedCandidateCount) / \(latestBatch.candidateCount)", compact: true)
                StatRow(label: "Elapsed", value: formattedSeconds(latestBatch.elapsedSeconds), compact: true)
                StatRow(label: "Throughput", value: formattedThroughput(latestBatch), compact: true)
                StatRow(label: "Accelerator", value: latestBatch.acceleratorDevice, compact: true)
                StatRow(label: "Policy", value: policyLabel(latestBatch), compact: true)
                StatRow(label: "Observation", value: observationLabel(latestBatch), compact: true)
                StatRow(label: "World", value: worldLabel(latestBatch), compact: true)
                StatRow(label: "Action", value: actionLabel(latestBatch), compact: true)
            } else {
                Text("Waiting for the first vectorized batch artifact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 260, idealWidth: 320, maxWidth: 380, alignment: .topLeading)
    }

    private var throughputChart: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            HStack {
                Text("Execution Throughput")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(throughputSummaryLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if throughputSamples.isEmpty {
                ContentUnavailableView(
                    "No completed batches",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Throughput appears from live candidate events and vectorized batch artifacts.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(throughputSamples) { sample in
                    LineMark(
                        x: .value("Generation", sample.generationIndex),
                        y: .value("Candidates/sec", sample.throughput)
                    )
                    .foregroundStyle(by: .value("Kind", sample.kind))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Generation", sample.generationIndex),
                        y: .value("Candidates/sec", sample.throughput)
                    )
                    .foregroundStyle(by: .value("Kind", sample.kind))
                }
                .chartXAxisLabel("generation")
                .chartYAxisLabel("candidates/sec")
                .frame(minHeight: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var throughputSummaryLabel: String {
        let liveCount = liveThroughputSamples.count
        if liveCount > 0 {
            return "\(liveCount) live / \(evaluationBatches.count) eval / \(variationBatches.count) variation"
        }
        return "\(evaluationBatches.count) eval / \(variationBatches.count) variation"
    }

    private var batchHistory: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            Text("Recent Batches")
                .font(.callout.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: KuyuSpacing.md, verticalSpacing: KuyuSpacing.xs) {
                GridRow {
                    header("Type")
                    header("Seed")
                    header("Gen")
                    header("Candidates")
                    header("Throughput")
                    header("Execution")
                    header("Artifact")
                }
                Divider()
                    .gridCellColumns(7)

                ForEach(recentBatches) { batch in
                    GridRow {
                        Text(batch.kind.rawValue)
                        Text(batch.seed)
                        Text("g\(batch.generationIndex)")
                        Text("\(batch.completedCandidateCount)/\(batch.candidateCount)")
                        Text(formattedThroughput(batch))
                        Text(shortExecutionLabel(batch))
                            .foregroundStyle(executionColor(batch))
                        Text(URL(fileURLWithPath: batch.artifactPath).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    private var recentBatches: [LearningCampaignVectorizedBatchState] {
        Array(batches.suffix(8).reversed())
    }

    private var throughputSamples: [VectorizedThroughputSample] {
        let persisted: [VectorizedThroughputSample] = batches.compactMap { batch in
            guard batch.elapsedSeconds > 0 else { return nil }
            return VectorizedThroughputSample(
                id: batch.id,
                generationIndex: batch.generationIndex,
                kind: batch.kind.rawValue,
                throughput: Double(batch.completedCandidateCount) / batch.elapsedSeconds
            )
        }
        return persisted + liveThroughputSamples
    }

    private var liveThroughputSamples: [VectorizedThroughputSample] {
        guard let state else { return [] }
        return state.progressEvents.compactMap { record -> VectorizedThroughputSample? in
            guard record.event == "candidate-evaluated",
                  let generationIndex = record.generationIndex,
                  let candidateID = record.candidateID,
                  let throughput = record.workerThroughput,
                  throughput.isFinite,
                  throughput > 0 else {
                return nil
            }
            return VectorizedThroughputSample(
                id: "live-\(record.seed ?? "seed")-g\(generationIndex)-\(candidateID)",
                generationIndex: generationIndex,
                kind: record.tensorSummary == true ? "live tensor" : "live",
                throughput: throughput
            )
        }
    }

    private func header(_ value: String) -> some View {
        Text(value)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func formattedSeconds(_ value: Double) -> String {
        guard value.isFinite else { return "--" }
        return String(format: "%.2fs", value)
    }

    private func formattedThroughput(_ batch: LearningCampaignVectorizedBatchState) -> String {
        guard batch.elapsedSeconds > 0 else { return "--" }
        return String(format: "%.2f/s", Double(batch.completedCandidateCount) / batch.elapsedSeconds)
    }

    private func formattedThroughput(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return String(format: "%.2f/s", value)
    }

    private var acceleratorName: String {
        state?.latestAcceleratorDevice ?? state?.accelerator?.acceleratorLabel ?? "Metal"
    }

    private func liveShapeLabel(_ record: LearningCampaignProgressRecord) -> String {
        let population = record.vectorizedPopulationSize.map { "B\($0)" } ?? "B?"
        let worlds = record.vectorizedWorldCount.map { "W\($0)" } ?? "W?"
        let history = record.vectorizedHistoryLength.map { "H\($0)" } ?? "H?"
        let observation = record.vectorizedObservationDimension.map { "obs\($0)" } ?? "obs?"
        let action = record.vectorizedActionDimension.map { "act\($0)" } ?? "act?"
        return "\(population) \(worlds) \(history) \(observation) \(action)"
    }

    private func policyLabel(_ batch: LearningCampaignVectorizedBatchState) -> String {
        batch.policyExecutionMode ?? (batch.kind == .variation ? "MLX weight variation" : "--")
    }

    private func observationLabel(_ batch: LearningCampaignVectorizedBatchState) -> String {
        batch.observationExecutionMode ?? "--"
    }

    private func worldLabel(_ batch: LearningCampaignVectorizedBatchState) -> String {
        batch.worldExecutionMode ?? "--"
    }

    private func actionLabel(_ batch: LearningCampaignVectorizedBatchState) -> String {
        guard let encoding = batch.actionEncoding else { return "--" }
        if let dimension = batch.worldActiveActionDimension {
            return "\(encoding) / active \(dimension)"
        }
        return encoding
    }

    private func shortExecutionLabel(_ batch: LearningCampaignVectorizedBatchState) -> String {
        switch batch.kind {
        case .variation:
            return "MLX variation"
        case .evaluation:
            if batch.worldExecutionMode?.hasPrefix("mlx-tensor-") == true {
                return "GPU tensor world"
            }
            return "materialized world"
        }
    }

    private func executionColor(_ batch: LearningCampaignVectorizedBatchState) -> Color {
        switch shortExecutionLabel(batch) {
        case "GPU tensor world":
            return .green
        case "MLX variation":
            return .cyan
        default:
            return .orange
        }
    }
}

private struct VectorizedThroughputSample: Identifiable {
    let id: String
    let generationIndex: Int
    let kind: String
    let throughput: Double
}
