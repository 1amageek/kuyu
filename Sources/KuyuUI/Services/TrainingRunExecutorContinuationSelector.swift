import Foundation
import KuyuTraining

struct TrainingRunExecutorContinuationSelector: TrainingContinuationSelecting {
    private let executor: any AnyTrainingRunExecuting

    init(executor: any AnyTrainingRunExecuting) {
        self.executor = executor
    }

    func continuationSelection(from artifactRoot: URL) throws -> TrainingContinuationSelection {
        try executor.continuationSelection(from: artifactRoot)
    }
}
