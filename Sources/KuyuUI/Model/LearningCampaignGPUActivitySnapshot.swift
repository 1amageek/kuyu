import Foundation

struct LearningCampaignGPUActivitySnapshot: Sendable, Equatable {
    let statusLabel: String
    let acceleratorLabel: String
    let latestExecutionLabel: String
    let latestThroughput: Double?
    let peakThroughput: Double?
    let gpuBackedEventCount: Int
    let knownEventCount: Int
    let gpuBackedBatchCount: Int
    let totalBatchCount: Int
    let latestBatchFillFraction: Double?
    let currentAllocatedBytes: UInt64?
    let recommendedMaxWorkingSetBytes: UInt64?

    init(
        batches: [LearningCampaignVectorizedBatchState],
        progressEvents: [LearningCampaignProgressRecord],
        acceleratorLabel: String?,
        currentAllocatedBytes: UInt64? = nil,
        recommendedMaxWorkingSetBytes: UInt64? = nil
    ) {
        let relevantEvents = progressEvents.filter(Self.isGPURelevantEvent)
        let latestEvent = relevantEvents.last
        let latestBatch = Self.latestBatch(in: batches)
        let latestUsesGPU = latestEvent.map(Self.recordUsesGPU)
            ?? latestBatch.map(Self.batchUsesGPU)
            ?? false

        self.statusLabel = latestUsesGPU ? "active" : (acceleratorLabel == nil ? "unavailable" : "ready")
        self.acceleratorLabel = acceleratorLabel ?? "--"
        self.latestExecutionLabel = latestEvent.map(Self.executionLabel(record:))
            ?? latestBatch.map(Self.executionLabel(batch:))
            ?? "--"
        self.latestThroughput = latestEvent?.workerThroughput.flatMap(Self.finitePositive)
            ?? latestBatch.flatMap(Self.throughput(batch:))

        let eventThroughputs = relevantEvents.compactMap { event in
            event.workerThroughput.flatMap(Self.finitePositive)
        }
        let batchThroughputs = batches.compactMap(Self.throughput(batch:))
        self.peakThroughput = (eventThroughputs + batchThroughputs).max()

        self.gpuBackedEventCount = relevantEvents.filter(Self.recordUsesGPU).count
        self.knownEventCount = relevantEvents.count
        self.gpuBackedBatchCount = batches.filter(Self.batchUsesGPU).count
        self.totalBatchCount = batches.count
        self.latestBatchFillFraction = latestBatch.flatMap(Self.batchFillFraction(batch:))
        self.currentAllocatedBytes = currentAllocatedBytes
        self.recommendedMaxWorkingSetBytes = recommendedMaxWorkingSetBytes
    }

    var gpuBackedEventFraction: Double? {
        guard knownEventCount > 0 else { return nil }
        return Double(gpuBackedEventCount) / Double(knownEventCount)
    }

    var gpuBackedBatchFraction: Double? {
        guard totalBatchCount > 0 else { return nil }
        return Double(gpuBackedBatchCount) / Double(totalBatchCount)
    }

    var metalMemoryFraction: Double? {
        guard let currentAllocatedBytes,
              let recommendedMaxWorkingSetBytes,
              recommendedMaxWorkingSetBytes > 0 else {
            return nil
        }
        return min(1, Double(currentAllocatedBytes) / Double(recommendedMaxWorkingSetBytes))
    }

    private static func isGPURelevantEvent(_ record: LearningCampaignProgressRecord) -> Bool {
        record.event == "candidate-evaluated"
            && (
                record.gpuAcceleration != nil ||
                record.tensorWorldBatch != nil ||
                record.tensorSummary != nil ||
                record.workerThroughput != nil
            )
    }

    private static func recordUsesGPU(_ record: LearningCampaignProgressRecord) -> Bool {
        record.gpuAcceleration == true ||
            record.tensorWorldBatch == true ||
            record.tensorSummary == true
    }

    private static func batchUsesGPU(_ batch: LearningCampaignVectorizedBatchState) -> Bool {
        switch batch.kind {
        case .variation:
            return !batch.acceleratorDevice.isEmpty
                && batch.acceleratorDevice.lowercased() != "cpu"
                && batch.acceleratorDevice.lowercased() != "unavailable"
        case .evaluation:
            return batch.worldExecutionMode?.hasPrefix("mlx-tensor-") == true ||
                batch.policyExecutionMode?.lowercased().contains("mlx") == true
        }
    }

    private static func executionLabel(record: LearningCampaignProgressRecord) -> String {
        if record.tensorWorldBatch == true {
            return "GPU tensor world"
        }
        if record.tensorSummary == true {
            return "GPU tensor summary"
        }
        if record.gpuAcceleration == true {
            return "MLX GPU"
        }
        return "CPU"
    }

    private static func executionLabel(batch: LearningCampaignVectorizedBatchState) -> String {
        switch batch.kind {
        case .variation:
            return "MLX variation"
        case .evaluation:
            if batch.worldExecutionMode?.hasPrefix("mlx-tensor-") == true {
                return "GPU tensor world"
            }
            if batch.policyExecutionMode?.lowercased().contains("mlx") == true {
                return "MLX evaluation"
            }
            return "CPU evaluation"
        }
    }

    private static func throughput(batch: LearningCampaignVectorizedBatchState) -> Double? {
        guard batch.elapsedSeconds > 0 else { return nil }
        return finitePositive(Double(batch.completedCandidateCount) / batch.elapsedSeconds)
    }

    private static func latestBatch(
        in batches: [LearningCampaignVectorizedBatchState]
    ) -> LearningCampaignVectorizedBatchState? {
        batches.max { lhs, rhs in
            if lhs.generationIndex != rhs.generationIndex {
                return lhs.generationIndex < rhs.generationIndex
            }
            if lhs.artifactPath != rhs.artifactPath {
                return lhs.artifactPath < rhs.artifactPath
            }
            return lhs.seed < rhs.seed
        }
    }

    private static func batchFillFraction(batch: LearningCampaignVectorizedBatchState) -> Double? {
        guard batch.candidateCount > 0 else { return nil }
        return min(1, Double(batch.completedCandidateCount) / Double(batch.candidateCount))
    }

    private static func finitePositive(_ value: Double) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        return value
    }
}
