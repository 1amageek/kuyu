import Foundation

public struct LogStore {
    public enum LogError: Error, Equatable {
        case encodingFailed
        case directoryUnavailable
    }

    public init() {}

    public func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw LogError.encodingFailed
        }
        try data.write(to: url)
    }

    public func ensureDirectory(_ url: URL) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw LogError.directoryUnavailable
            }
            return
        }
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
