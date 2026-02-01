import Logging

public struct KuyukaiLoggerFactory {
    private static let bootstrap: Void = {
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardError(label: label)
        }
    }()

    public init() {}

    public func make(label: String, level: Logger.Level) -> Logger {
        _ = KuyukaiLoggerFactory.bootstrap
        var logger = Logger(label: label)
        logger.logLevel = level
        return logger
    }
}
