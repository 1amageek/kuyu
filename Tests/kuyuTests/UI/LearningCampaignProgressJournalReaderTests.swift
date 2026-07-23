import Foundation
import KuyuMLXCampaignContracts
import KuyuTraining
@testable import KuyuUI
import Testing

@Suite("Learning campaign incremental progress journal")
struct LearningCampaignProgressJournalReaderTests {
    @Test(.timeLimit(.minutes(1)))
    func decodesOnlyAppendedCompleteLines() throws {
        let root = try temporaryDirectory()
        defer { removeDirectory(root) }
        let journal = root.appendingPathComponent("progress.jsonl")
        let first = progressEvent(index: 1)
        let second = progressEvent(index: 2)
        let firstLine = try encodedLine(first)
        let secondLine = try encodedLine(second)
        let split = secondLine.count / 2
        var initial = firstLine
        initial.append(secondLine.prefix(split))
        try initial.write(to: journal, options: .atomic)
        var reader = LearningCampaignProgressJournalReader()

        let initialRead = try reader.read(from: journal)
        #expect(initialRead.records == [first])
        #expect(initialRead.newlyDecodedRecordCount == 1)

        try append(Data(secondLine.dropFirst(split)), to: journal)
        let appendedRead = try reader.read(from: journal)
        #expect(appendedRead.records == [first, second])
        #expect(appendedRead.newlyDecodedRecordCount == 1)

        let unchangedRead = try reader.read(from: journal)
        #expect(unchangedRead.records == [first, second])
        #expect(unchangedRead.newlyDecodedRecordCount == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func resetsWhenJournalIsAtomicallyReplaced() throws {
        let root = try temporaryDirectory()
        defer { removeDirectory(root) }
        let journal = root.appendingPathComponent("progress.jsonl")
        let first = progressEvent(index: 1)
        let replacement = progressEvent(index: 9)
        try encodedLine(first).write(to: journal, options: .atomic)
        var reader = LearningCampaignProgressJournalReader()
        _ = try reader.read(from: journal)

        try encodedLine(replacement).write(to: journal, options: .atomic)
        let result = try reader.read(from: journal)

        #expect(result.records == [replacement])
        #expect(result.newlyDecodedRecordCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func reportsLineNumberForSemanticallyInvalidWorkProgress() throws {
        let root = try temporaryDirectory()
        defer { removeDirectory(root) }
        let journal = root.appendingPathComponent("progress.jsonl")
        var bytes = try encodedLine(progressEvent(index: 1))
        bytes.append(try invalidWorkProgressLine())
        try bytes.write(to: journal, options: .atomic)
        var reader = LearningCampaignProgressJournalReader()

        do {
            _ = try reader.read(from: journal)
            Issue.record("Expected invalid progress record")
        } catch let error as LearningCampaignProgressJournalReadError {
            guard case .invalidRecord(let line, let description) = error else {
                Issue.record("Unexpected reader error: \(error)")
                return
            }
            #expect(line == 2)
            #expect(description.contains("invalidUnitCount"))
        }

        do {
            _ = try reader.read(from: journal)
            Issue.record("Expected the unchanged invalid record to remain visible.")
        } catch let error as LearningCampaignProgressJournalReadError {
            guard case .invalidRecord(let line, _) = error else {
                Issue.record("Unexpected repeated reader error: \(error)")
                return
            }
            #expect(line == 2)
        }

        let replacement = progressEvent(index: 9)
        try encodedLine(replacement).write(to: journal, options: .atomic)
        let recovered = try reader.read(from: journal)
        #expect(recovered.records == [replacement])
        #expect(recovered.newlyDecodedRecordCount == 1)
    }

    private func progressEvent(index: Int) -> LearningCampaignProgressEvent {
        LearningCampaignProgressEvent(
            event: "resource-sampled",
            timestamp: Date(timeIntervalSince1970: Double(index)),
            phase: "resource",
            message: "sample-\(index)"
        )
    }

    private func encodedLine(_ event: LearningCampaignProgressEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(event)
        data.append(0x0A)
        return data
    }

    private func invalidWorkProgressLine() throws -> Data {
        let scope = try TrainingWorkScope(runID: "run")
        let unit = try TrainingWorkUnit(kind: .controlStep, identifier: "step")
        let record = InvalidProgressEventRecord(
            event: "work-progress",
            timestamp: Date(timeIntervalSince1970: 2),
            workProgress: InvalidWorkProgressRecord(
                scope: scope,
                phase: .rollout,
                state: .advanced,
                unit: unit,
                completedUnitCount: 2,
                totalUnitCount: 1,
                timestamp: Date(timeIntervalSince1970: 2)
            ),
            failureReasons: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(record)
        data.append(0x0A)
        return data
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuyu-progress-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { handle.closeFile() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func removeDirectory(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to remove test directory: \(error)")
        }
    }
}

private struct InvalidProgressEventRecord: Encodable {
    let event: String
    let timestamp: Date
    let workProgress: InvalidWorkProgressRecord
    let failureReasons: [String]
}

private struct InvalidWorkProgressRecord: Encodable {
    let scope: TrainingWorkScope
    let phase: TrainingWorkPhase
    let state: TrainingWorkState
    let unit: TrainingWorkUnit
    let completedUnitCount: Int
    let totalUnitCount: Int
    let timestamp: Date
}
