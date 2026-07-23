import Foundation
import KuyuTraining

struct UnavailableTrainingRunExecutor: AnyTrainingRunExecuting {
    struct AvailabilityError: Error, LocalizedError, Sendable, Equatable {
        let reason: String

        var errorDescription: String? {
            "Training worker is unavailable: \(reason)"
        }
    }

    let error: AvailabilityError

    init(reason: String) {
        self.error = AvailabilityError(reason: reason)
    }

    func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        throw error
    }

    func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        throw error
    }

    func continuationSelection(
        from artifactRoot: URL
    ) throws -> TrainingContinuationSelection {
        throw error
    }

    func validate(_ request: TrainingRunRequest) throws {
        throw error
    }

    func validate(_ request: TrainingResumeRequest) throws {
        throw error
    }
}
