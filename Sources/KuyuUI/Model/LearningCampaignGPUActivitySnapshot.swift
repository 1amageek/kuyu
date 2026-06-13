import Foundation

struct LearningCampaignGPUActivitySnapshot: Sendable, Equatable {
    enum Status: String, Sendable, Equatable {
        case active
        case ready
        case unavailable

        var label: String { rawValue }
    }

    enum ExecutionEvidence: Sendable, Equatable {
        case cpu
        case mlxGPU
        case gpuTensorWorld
        case gpuTensorSummary
        case mlxVariation
        case mlxEvaluation
        case cpuEvaluation
        case unknown

        var label: String {
            switch self {
            case .cpu:
                return "CPU"
            case .mlxGPU:
                return "MLX GPU"
            case .gpuTensorWorld:
                return "GPU tensor world"
            case .gpuTensorSummary:
                return "GPU tensor summary"
            case .mlxVariation:
                return "MLX variation"
            case .mlxEvaluation:
                return "MLX evaluation"
            case .cpuEvaluation:
                return "CPU evaluation"
            case .unknown:
                return "--"
            }
        }

        var usesGPU: Bool {
            switch self {
            case .mlxGPU, .gpuTensorWorld, .gpuTensorSummary, .mlxVariation, .mlxEvaluation:
                return true
            case .cpu, .cpuEvaluation, .unknown:
                return false
            }
        }
    }

    let status: Status
    let acceleratorLabel: String
    let latestExecution: ExecutionEvidence
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
        let latestExecution = latestEvent.map(Self.executionEvidence(record:))
            ?? latestBatch.map(Self.executionEvidence(batch:))
            ?? .unknown
        let latestUsesGPU = latestExecution.usesGPU

        self.status = latestUsesGPU ? .active : (acceleratorLabel == nil ? .unavailable : .ready)
        self.acceleratorLabel = acceleratorLabel ?? "--"
        self.latestExecution = latestExecution
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

    var statusLabel: String {
        status.label
    }

    var latestExecutionLabel: String {
        latestExecution.label
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
        executionEvidence(record: record).usesGPU
    }

    private static func batchUsesGPU(_ batch: LearningCampaignVectorizedBatchState) -> Bool {
        executionEvidence(batch: batch).usesGPU
    }

    private static func executionEvidence(record: LearningCampaignProgressRecord) -> ExecutionEvidence {
        if record.tensorWorldBatch == true {
            return .gpuTensorWorld
        }
        if record.tensorSummary == true {
            return .gpuTensorSummary
        }
        if record.gpuAcceleration == true {
            return .mlxGPU
        }
        return .cpu
    }

    private static func executionEvidence(batch: LearningCampaignVectorizedBatchState) -> ExecutionEvidence {
        switch batch.kind {
        case .variation:
            let normalizedDevice = batch.acceleratorDevice.lowercased()
            if batch.acceleratorDevice.isEmpty ||
                normalizedDevice == "cpu" ||
                normalizedDevice == "unavailable" {
                return .cpu
            }
            return .mlxVariation
        case .evaluation:
            if batch.worldExecutionMode?.hasPrefix("mlx-tensor-") == true {
                return .gpuTensorWorld
            }
            if batch.policyExecutionMode?.lowercased().contains("mlx") == true {
                return .mlxEvaluation
            }
            return .cpuEvaluation
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
