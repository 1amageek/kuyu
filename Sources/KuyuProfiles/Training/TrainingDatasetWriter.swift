import Foundation
import KuyuCore

public struct TrainingDatasetWriter {
    public init() {}

    public func write(log: SimulationLog, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let records = buildRecords(from: log)
        let metadata = TrainingDatasetMetadata(
            scenarioId: log.scenarioId.rawValue,
            seed: log.seed.rawValue,
            timeStep: log.timeStep.delta,
            determinismTier: log.determinism.tier.rawValue,
            configHash: log.configHash,
            channelCount: maxChannelCount(records),
            driveCount: maxDriveCount(records),
            recordCount: records.count,
            failureReason: log.failureReason?.rawValue,
            failureTime: log.failureTime
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        let metaURL = directory.appendingPathComponent("meta.json")
        let metaData = try encoder.encode(metadata)
        try metaData.write(to: metaURL, options: [.atomic])

        let recordsURL = directory.appendingPathComponent("records.jsonl")
        FileManager.default.createFile(atPath: recordsURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: recordsURL)
        defer {
            do {
                try handle.close()
            } catch {
                assertionFailure("Failed to close training dataset handle: \(error)")
            }
        }

        for record in records {
            let data = try encoder.encode(record)
            handle.write(data)
            handle.write(Data("\n".utf8))
        }

        return directory
    }

    private func buildRecords(from log: SimulationLog) -> [TrainingDatasetRecord] {
        log.events.map { event in
            let sensors = event.sensorSamples.map { sample in
                TrainingSensorSample(
                    channelIndex: sample.channelIndex,
                    value: sample.value,
                    timestamp: sample.timestamp
                )
            }
            let drives = event.driveIntents.map { intent in
                TrainingDriveIntent(
                    driveIndex: intent.index.rawValue,
                    value: intent.activation,
                    parameters: intent.parameters
                )
            }
            let reflex = event.reflexCorrections.map { correction in
                TrainingReflexCorrection(
                    driveIndex: correction.driveIndex.rawValue,
                    clamp: correction.clampMultiplier,
                    damping: correction.damping,
                    delta: correction.delta
                )
            }
            return TrainingDatasetRecord(
                time: event.time.time,
                sensors: sensors,
                driveIntents: drives,
                reflexCorrections: reflex
            )
        }
    }

    private func maxChannelCount(_ records: [TrainingDatasetRecord]) -> Int {
        let maxIndex = records.flatMap { $0.sensors }.map { Int($0.channelIndex) }.max() ?? -1
        return maxIndex + 1
    }

    private func maxDriveCount(_ records: [TrainingDatasetRecord]) -> Int {
        let maxIndex = records.flatMap { $0.driveIntents }.map { Int($0.driveIndex) }.max() ?? -1
        return maxIndex + 1
    }
}
