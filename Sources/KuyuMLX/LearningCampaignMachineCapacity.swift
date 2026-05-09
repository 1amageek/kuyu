import Foundation

public struct LearningCampaignMachineCapacity: Sendable, Codable, Equatable {
    public let activeProcessorCount: Int
    public let physicalMemoryBytes: UInt64

    public init(activeProcessorCount: Int, physicalMemoryBytes: UInt64) {
        self.activeProcessorCount = max(1, activeProcessorCount)
        self.physicalMemoryBytes = physicalMemoryBytes
    }

    public static func current() -> LearningCampaignMachineCapacity {
        LearningCampaignMachineCapacity(
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    public var reservedProcessorCount: Int {
        min(2, max(0, activeProcessorCount - 1))
    }

    public var usableProcessorSlots: Int {
        max(1, activeProcessorCount - reservedProcessorCount)
    }

    public var memoryLimitedCandidateSlots: Int {
        let bytesPerCandidate: UInt64 = 4 * 1_024 * 1_024 * 1_024
        guard physicalMemoryBytes > 0 else { return usableProcessorSlots }
        return max(1, Int(physicalMemoryBytes / bytesPerCandidate))
    }

    public var summary: String {
        let memoryGB = Double(physicalMemoryBytes) / 1_073_741_824
        return "\(activeProcessorCount) CPU / \(String(format: "%.0f", memoryGB)) GB"
    }

    public func recommendation(
        population: Int,
        suiteCount: Int,
        episodes: Int
    ) -> LearningCampaignParallelismRecommendation {
        let normalizedPopulation = max(1, population)
        let rolloutShardsPerCandidate = max(1, suiteCount) * max(1, episodes)
        let candidateSlotsByCPU = max(1, usableProcessorSlots / rolloutShardsPerCandidate)
        let candidateConcurrency = max(1, min(
            normalizedPopulation,
            candidateSlotsByCPU,
            memoryLimitedCandidateSlots
        ))
        let workerCount = max(1, min(
            rolloutShardsPerCandidate,
            usableProcessorSlots / candidateConcurrency
        ))
        return LearningCampaignParallelismRecommendation(
            machine: self,
            workerCount: workerCount,
            candidateEvaluationConcurrency: candidateConcurrency,
            rolloutShardsPerCandidate: rolloutShardsPerCandidate,
            totalParallelSlots: workerCount * candidateConcurrency
        )
    }
}
