import Foundation
import KuyuTraining
import Synchronization

/// Thread-safe accumulator that folds `TrainingRunEvent`s into per-iteration
/// summaries for journaling under the training-run contract.
///
/// The orchestrator emits events as an iteration progresses; an iteration is
/// complete once the next iteration boundary is reached (or the run returns).
/// `drainCompleted(before:)` hands back exactly those finished iterations so
/// the caller can append gap-free journal records.
final class TrainingRunEventCollector: Sendable {
    /// Summary of one finished orchestrator iteration (1-based).
    struct CompletedIteration: Sendable {
        let orchestratorIteration: Int
        let metrics: [String: Double]
        let checkpointURL: URL?
    }

    private struct IterationAccumulator {
        var metrics: [String: Double] = [:]
        var checkpointURL: URL?
    }

    private struct State {
        var accumulators: [Int: IterationAccumulator] = [:]
    }

    private let state = Mutex(State())

    func ingest(_ event: TrainingRunEvent) {
        switch event {
        case .suiteCompleted(let iteration, let output, let score):
            state.withLock { state in
                var accumulator = state.accumulators[iteration] ?? IterationAccumulator()
                accumulator.metrics["score"] = score
                accumulator.metrics["suitePassed"] = output.summary.suitePassed ? 1 : 0
                if let overshoot = output.summary.aggregate.worstOvershootDegrees {
                    accumulator.metrics["worstOvershootDegrees"] = overshoot
                }
                if let recovery = output.summary.aggregate.averageRecoveryTime {
                    accumulator.metrics["averageRecoveryTime"] = recovery
                }
                if let hf = output.summary.aggregate.averageHfStabilityScore {
                    accumulator.metrics["averageHfStabilityScore"] = hf
                }
                state.accumulators[iteration] = accumulator
            }
        case .datasetExported(let iteration, _, let count):
            state.withLock { state in
                var accumulator = state.accumulators[iteration] ?? IterationAccumulator()
                accumulator.metrics["datasetSampleCount"] = Double(count)
                state.accumulators[iteration] = accumulator
            }
        case .trainingCompleted(let iteration, let result):
            state.withLock { state in
                var accumulator = state.accumulators[iteration] ?? IterationAccumulator()
                accumulator.metrics["trainingLoss"] = result.finalLoss
                accumulator.checkpointURL = result.candidateCheckpointURL
                state.accumulators[iteration] = accumulator
            }
        default:
            break
        }
    }

    /// Removes and returns summaries for orchestrator iterations strictly
    /// before `iteration`, in iteration order.
    func drainCompleted(before iteration: Int) -> [CompletedIteration] {
        state.withLock { state in
            let finished = state.accumulators.keys.filter { $0 < iteration }.sorted()
            return finished.map { key in
                let accumulator = state.accumulators.removeValue(forKey: key)
                return CompletedIteration(
                    orchestratorIteration: key,
                    metrics: accumulator?.metrics ?? [:],
                    checkpointURL: accumulator?.checkpointURL
                )
            }
        }
    }

    /// Removes and returns all remaining iteration summaries, in order.
    func drainAll() -> [CompletedIteration] {
        drainCompleted(before: Int.max)
    }
}
