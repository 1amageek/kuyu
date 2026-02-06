import Logging

public enum UILoggingBootstrap {
    public static let buffer: UILogBuffer = {
        let buffer = UILogBuffer()
        LoggingSystem.bootstrap { label in
            UILogHandler(label: label, buffer: buffer)
        }
        return buffer
    }()
}
