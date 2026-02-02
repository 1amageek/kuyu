import Logging

enum LogLevelOption: String, CaseIterable, Identifiable {
    case trace
    case debug
    case info
    case notice
    case warning
    case error
    case critical

    var id: String { rawValue }

    var level: Logger.Level {
        switch self {
        case .trace: return .trace
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .warning: return .warning
        case .error: return .error
        case .critical: return .critical
        }
    }

    static func from(level: Logger.Level) -> LogLevelOption {
        switch level {
        case .trace: return .trace
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .warning: return .warning
        case .error: return .error
        case .critical: return .critical
        }
    }
}
