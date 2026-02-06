import Foundation
import KuyuCore
import Synchronization

/// Thread-safe ring buffer for collecting training data online during simulation.
///
/// Inspired by Micro-World's online data collection pipeline, this buffer
/// accumulates training records during simulation and supports random
/// sampling for online/on-policy training.
public final class OnlineDataBuffer: Sendable {
    private struct Storage: Sendable {
        var records: [TrainingDatasetRecord]
        var writeIndex: Int
        let maxRecords: Int
        var totalWritten: Int

        init(maxRecords: Int) {
            self.records = []
            self.records.reserveCapacity(min(maxRecords, 1024))
            self.writeIndex = 0
            self.maxRecords = maxRecords
            self.totalWritten = 0
        }
    }

    private let storage: Mutex<Storage>

    public init(maxRecords: Int) {
        self.storage = Mutex(Storage(maxRecords: maxRecords))
    }

    /// Append a single training record to the buffer (ring buffer semantics).
    public func append(_ record: TrainingDatasetRecord) {
        storage.withLock { state in
            if state.records.count < state.maxRecords {
                state.records.append(record)
            } else {
                state.records[state.writeIndex] = record
            }
            state.writeIndex = (state.writeIndex + 1) % state.maxRecords
            state.totalWritten += 1
        }
    }

    /// Append all records from a simulation log.
    public func appendFromLog(_ log: SimulationLog) {
        let dt = log.timeStep.delta
        for step in log.events {
            let sensors = step.sensorSamples.map { sample in
                TrainingSensorSample(
                    channelIndex: sample.channelIndex,
                    value: sample.value,
                    timestamp: sample.timestamp
                )
            }
            let drives = step.driveIntents.map { intent in
                TrainingDriveIntent(
                    driveIndex: intent.index.rawValue,
                    value: intent.activation,
                    parameters: intent.parameters
                )
            }
            let corrections = step.reflexCorrections.map { correction in
                TrainingReflexCorrection(
                    driveIndex: correction.driveIndex.rawValue,
                    clamp: correction.clampMultiplier,
                    damping: correction.damping,
                    delta: correction.delta
                )
            }
            let record = TrainingDatasetRecord(
                time: step.time.time,
                sensors: sensors,
                driveIntents: drives,
                reflexCorrections: corrections
            )
            append(record)
            _ = dt // suppress unused warning
        }
    }

    /// Sample `count` random records using the provided PRNG.
    public func sample(count: Int, rng: inout SplitMix64) -> [TrainingDatasetRecord] {
        storage.withLock { state in
            guard !state.records.isEmpty else { return [] }
            let available = state.records.count
            return (0..<count).map { _ in
                let index = Int(rng.next() % UInt64(available))
                return state.records[index]
            }
        }
    }

    /// Return all records currently in the buffer (ordered by insertion).
    public func allRecords() -> [TrainingDatasetRecord] {
        storage.withLock { state in
            if state.records.count < state.maxRecords {
                return state.records
            }
            // Ring buffer: reorder from writeIndex
            let tail = Array(state.records[state.writeIndex...])
            let head = Array(state.records[..<state.writeIndex])
            return tail + head
        }
    }

    /// Current number of records in the buffer.
    public var count: Int {
        storage.withLock { $0.records.count }
    }

    /// Total number of records ever written (including overwritten ones).
    public var totalWritten: Int {
        storage.withLock { $0.totalWritten }
    }

    /// Remove all records from the buffer.
    public func clear() {
        storage.withLock { state in
            state.records.removeAll(keepingCapacity: true)
            state.writeIndex = 0
        }
    }
}
