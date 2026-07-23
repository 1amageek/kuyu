import Foundation
import KuyuTraining

public protocol TrainingContinuationSelecting: Sendable {
    func continuationSelection(from artifactRoot: URL) throws -> TrainingContinuationSelection
}
