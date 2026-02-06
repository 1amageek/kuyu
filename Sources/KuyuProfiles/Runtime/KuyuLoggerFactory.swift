import Logging
import KuyuCore

public struct KuyuLoggerFactory {
    private static let bootstrap: Void = {
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardError(label: label)
        }
    }()

    public init() {}

    public func make(label: String, level: Logger.Level) -> Logger {
        _ = KuyuLoggerFactory.bootstrap
        var logger = Logger(label: label)
        logger.logLevel = level
        return logger
    }
}
