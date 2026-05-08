import KuyuTraining
import Synchronization

final class EvolutionEventContinuationBox: Sendable {
    private let storage = Mutex<AsyncStream<EvolutionRunEvent>.Continuation?>(nil)

    func set(_ continuation: AsyncStream<EvolutionRunEvent>.Continuation) {
        storage.withLock { value in
            value = continuation
        }
    }

    func yield(_ event: EvolutionRunEvent) {
        let continuation = storage.withLock { value in
            value
        }
        continuation?.yield(event)
    }

    func finish() {
        storage.withLock { value in
            value?.finish()
            value = nil
        }
    }
}
