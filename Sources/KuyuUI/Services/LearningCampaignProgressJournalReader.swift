import Darwin
import Foundation
import KuyuMLXCampaignContracts

enum LearningCampaignProgressJournalReadError: Error, Equatable {
    case openFailed(path: String, description: String)
    case inspectionFailed(path: String, description: String)
    case nonRegularFile(String)
    case unexpectedOwner(path: String, owner: UInt32)
    case unsafePermissions(path: String, mode: UInt16)
    case readFailed(path: String, description: String)
    case fileChangedDuringRead(String)
    case oversizedPartialRecord(byteCount: Int)
    case invalidRecord(line: Int, description: String)
}

struct LearningCampaignProgressJournalReadResult: Sendable, Equatable {
    let records: [LearningCampaignProgressEvent]
    let newlyDecodedRecordCount: Int
}

struct LearningCampaignProgressJournalReader {
    private struct FileIdentity: Equatable {
        let systemNumber: UInt64
        let fileNumber: UInt64
    }

    private static let maximumRecordCount = 4_000
    private static let maximumReadByteCount = 4 * 1_024 * 1_024
    private static let maximumPartialRecordByteCount = 1 * 1_024 * 1_024

    private var url: URL?
    private var identity: FileIdentity?
    private var offset: UInt64 = 0
    private var partialLine = Data()
    private var lineNumber = 0
    private var records: [LearningCampaignProgressEvent] = []

    mutating func read(from journalURL: URL) throws -> LearningCampaignProgressJournalReadResult {
        let path = journalURL.path
        let descriptor = path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            if errno == ENOENT {
                reset(for: journalURL, identity: nil)
                return LearningCampaignProgressJournalReadResult(
                    records: [],
                    newlyDecodedRecordCount: 0
                )
            }
            throw LearningCampaignProgressJournalReadError.openFailed(
                path: path,
                description: Self.systemReason()
            )
        }
        defer { Darwin.close(descriptor) }

        let initialMetadata = try metadata(for: descriptor, path: path)
        let currentIdentity = fileIdentity(initialMetadata)
        let fileSize = UInt64(initialMetadata.st_size)
        let shouldReset = url != journalURL
            || identity != currentIdentity
            || fileSize < offset
        var nextOffset = shouldReset ? 0 : offset
        var nextPartialLine = shouldReset ? Data() : partialLine
        var nextLineNumber = shouldReset ? 0 : lineNumber
        var nextRecords = shouldReset ? [] : records

        guard fileSize > nextOffset else {
            commit(
                url: journalURL,
                identity: currentIdentity,
                offset: nextOffset,
                partialLine: nextPartialLine,
                lineNumber: nextLineNumber,
                records: nextRecords
            )
            return LearningCampaignProgressJournalReadResult(
                records: nextRecords,
                newlyDecodedRecordCount: 0
            )
        }

        let requestedByteCount = Int(
            min(
                fileSize - nextOffset,
                UInt64(Self.maximumReadByteCount)
            )
        )
        let appendedData = try data(
            from: descriptor,
            path: path,
            offset: nextOffset,
            byteCount: requestedByteCount
        )
        guard appendedData.count == requestedByteCount else {
            throw LearningCampaignProgressJournalReadError.fileChangedDuringRead(path)
        }
        nextOffset += UInt64(appendedData.count)
        var bytes = nextPartialLine
        bytes.append(appendedData)
        let decoded = try decodeCompleteLines(
            from: bytes,
            startingLineNumber: nextLineNumber,
            existingRecords: nextRecords
        )
        nextPartialLine = decoded.partialLine
        nextLineNumber = decoded.lineNumber
        nextRecords = decoded.records
        guard nextPartialLine.count <= Self.maximumPartialRecordByteCount else {
            throw LearningCampaignProgressJournalReadError.oversizedPartialRecord(
                byteCount: nextPartialLine.count
            )
        }

        let finalMetadata = try metadata(for: descriptor, path: path)
        guard fileIdentity(finalMetadata) == currentIdentity,
              UInt64(finalMetadata.st_size) >= nextOffset else {
            throw LearningCampaignProgressJournalReadError.fileChangedDuringRead(path)
        }
        commit(
            url: journalURL,
            identity: currentIdentity,
            offset: nextOffset,
            partialLine: nextPartialLine,
            lineNumber: nextLineNumber,
            records: nextRecords
        )
        return LearningCampaignProgressJournalReadResult(
            records: nextRecords,
            newlyDecodedRecordCount: decoded.decodedRecordCount
        )
    }

    private func decodeCompleteLines(
        from bytes: Data,
        startingLineNumber: Int,
        existingRecords: [LearningCampaignProgressEvent]
    ) throws -> (
        records: [LearningCampaignProgressEvent],
        partialLine: Data,
        lineNumber: Int,
        decodedRecordCount: Int
    ) {
        var decodedCount = 0
        var currentLineNumber = startingLineNumber
        var nextRecords = existingRecords
        var lineStart = bytes.startIndex
        while lineStart < bytes.endIndex,
              let newline = bytes[lineStart...].firstIndex(of: 0x0A) {
            currentLineNumber += 1
            var line = Data(bytes[lineStart..<newline])
            if line.last == 0x0D {
                line.removeLast()
            }
            if !line.allSatisfy(Self.isJSONWhitespace) {
                do {
                    nextRecords.append(
                        try decoder.decode(LearningCampaignProgressEvent.self, from: line)
                    )
                    decodedCount += 1
                } catch {
                    throw LearningCampaignProgressJournalReadError.invalidRecord(
                        line: currentLineNumber,
                        description: String(describing: error)
                    )
                }
            }
            lineStart = bytes.index(after: newline)
        }
        if nextRecords.count > Self.maximumRecordCount {
            nextRecords.removeFirst(nextRecords.count - Self.maximumRecordCount)
        }
        return (
            records: nextRecords,
            partialLine: Data(bytes[lineStart..<bytes.endIndex]),
            lineNumber: currentLineNumber,
            decodedRecordCount: decodedCount
        )
    }

    private mutating func commit(
        url: URL,
        identity: FileIdentity,
        offset: UInt64,
        partialLine: Data,
        lineNumber: Int,
        records: [LearningCampaignProgressEvent]
    ) {
        self.url = url
        self.identity = identity
        self.offset = offset
        self.partialLine = partialLine
        self.lineNumber = lineNumber
        self.records = records
    }

    private mutating func reset(for journalURL: URL, identity: FileIdentity?) {
        url = journalURL
        self.identity = identity
        offset = 0
        partialLine = Data()
        lineNumber = 0
        records = []
    }

    private func metadata(for descriptor: Int32, path: String) throws -> stat {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0 else {
            throw LearningCampaignProgressJournalReadError.inspectionFailed(
                path: path,
                description: Self.systemReason()
            )
        }
        guard value.st_mode & S_IFMT == S_IFREG else {
            throw LearningCampaignProgressJournalReadError.nonRegularFile(path)
        }
        guard value.st_uid == Darwin.getuid() else {
            throw LearningCampaignProgressJournalReadError.unexpectedOwner(
                path: path,
                owner: value.st_uid
            )
        }
        let permissions = value.st_mode & 0o777
        guard permissions & 0o022 == 0 else {
            throw LearningCampaignProgressJournalReadError.unsafePermissions(
                path: path,
                mode: UInt16(permissions)
            )
        }
        return value
    }

    private func fileIdentity(_ metadata: stat) -> FileIdentity {
        FileIdentity(
            systemNumber: UInt64(metadata.st_dev),
            fileNumber: UInt64(metadata.st_ino)
        )
    }

    private func data(
        from descriptor: Int32,
        path: String,
        offset: UInt64,
        byteCount: Int
    ) throws -> Data {
        var result = Data(count: byteCount)
        let readCount = try result.withUnsafeMutableBytes { bytes -> Int in
            guard let baseAddress = bytes.baseAddress else { return 0 }
            var totalRead = 0
            while totalRead < byteCount {
                let count = Darwin.pread(
                    descriptor,
                    baseAddress.advanced(by: totalRead),
                    byteCount - totalRead,
                    off_t(offset) + off_t(totalRead)
                )
                if count < 0, errno == EINTR {
                    continue
                }
                guard count >= 0 else {
                    throw LearningCampaignProgressJournalReadError.readFailed(
                        path: path,
                        description: Self.systemReason()
                    )
                }
                guard count > 0 else { break }
                totalRead += count
            }
            return totalRead
        }
        result.removeSubrange(readCount..<result.count)
        return result
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return decoder
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D
    }

    private static func systemReason() -> String {
        String(cString: strerror(errno))
    }
}
