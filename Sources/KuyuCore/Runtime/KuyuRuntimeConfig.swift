import Foundation
import Logging

public struct KuyuRuntimeConfig: Sendable, Equatable {
    public let logLevel: Logger.Level
    public let logLabel: String
    public let logDirectory: String?

    public init(logLevel: Logger.Level, logLabel: String, logDirectory: String?) {
        self.logLevel = logLevel
        self.logLabel = logLabel
        self.logDirectory = logDirectory
    }

    public static let `default` = KuyuRuntimeConfig(
        logLevel: .info,
        logLabel: "kuyu",
        logDirectory: nil
    )

    public static func parseLogLevel(_ value: String) -> Logger.Level {
        switch value.lowercased() {
        case "trace": return .trace
        case "debug": return .debug
        case "info": return .info
        case "notice": return .notice
        case "warning": return .warning
        case "error": return .error
        case "critical": return .critical
        default: return .info
        }
    }

    public var logDirectoryURL: URL? {
        guard let logDirectory, !logDirectory.isEmpty else { return nil }
        return URL(fileURLWithPath: logDirectory, isDirectory: true)
    }
}
