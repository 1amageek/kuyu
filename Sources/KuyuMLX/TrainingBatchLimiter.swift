import Foundation
import ManasMLXTraining

public struct TrainingBatchLimiter: Sendable, Equatable {
    public let limit: Int?
    public let currentCount: Int

    public init(limit: Int?, currentCount: Int = 0) {
        self.limit = limit
        self.currentCount = currentCount
    }

    public func select<T>(_ batches: [T]) -> [T] {
        guard let limit else { return batches }
        let remaining = max(0, limit - currentCount)
        guard remaining < batches.count else { return batches }
        guard remaining > 0 else { return [] }

        let sampler = ManasTrainingWindowSampler(maxBatches: remaining)
        return sampler.selectedWindowStarts(maxStart: batches.count - 1).map { batches[$0] }
    }
}
