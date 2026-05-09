import Foundation

public struct LearningCampaignParallelismRecommendation: Sendable, Codable, Equatable {
    public let machine: LearningCampaignMachineCapacity
    public let workerCount: Int
    public let candidateEvaluationConcurrency: Int
    public let rolloutShardsPerCandidate: Int
    public let totalParallelSlots: Int

    public init(
        machine: LearningCampaignMachineCapacity,
        workerCount: Int,
        candidateEvaluationConcurrency: Int,
        rolloutShardsPerCandidate: Int,
        totalParallelSlots: Int
    ) {
        self.machine = machine
        self.workerCount = max(1, workerCount)
        self.candidateEvaluationConcurrency = max(1, candidateEvaluationConcurrency)
        self.rolloutShardsPerCandidate = max(1, rolloutShardsPerCandidate)
        self.totalParallelSlots = max(1, totalParallelSlots)
    }

    public var utilization: Double {
        min(1, Double(totalParallelSlots) / Double(machine.usableProcessorSlots))
    }

    public var utilizationLabel: String {
        "\(Int((utilization * 100).rounded()))%"
    }

    public var summary: String {
        "\(candidateEvaluationConcurrency) candidates x \(workerCount) workers"
    }
}
