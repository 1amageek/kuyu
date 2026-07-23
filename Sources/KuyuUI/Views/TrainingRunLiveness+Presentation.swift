import KuyuTraining

extension TrainingRunLiveness {
    var displayLabel: String {
        switch self {
        case .live(let processIdentifier):
            return "live (pid \(processIdentifier))"
        case .finished(let status):
            return status.rawValue
        case .paused(let processAlive):
            return processAlive ? "paused" : "paused (writer dead)"
        case .interrupted:
            return "interrupted"
        }
    }

    var pillTone: StatusPill.Tone {
        switch self {
        case .live:
            return .info
        case .finished(let status):
            switch status {
            case .completed:
                return .success
            case .cancelled:
                return .neutral
            case .failed:
                return .danger
            case .running, .paused:
                return .warning
            }
        case .paused(let processAlive):
            return processAlive ? .warning : .danger
        case .interrupted:
            return .danger
        }
    }
}
