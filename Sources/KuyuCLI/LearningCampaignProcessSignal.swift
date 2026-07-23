import Darwin

enum LearningCampaignProcessSignal: Sendable, Equatable {
    case interrupt
    case termination

    init?(number: Int32) {
        switch number {
        case SIGINT:
            self = .interrupt
        case SIGTERM:
            self = .termination
        default:
            return nil
        }
    }

    var number: Int32 {
        switch self {
        case .interrupt: SIGINT
        case .termination: SIGTERM
        }
    }

    var exitCode: Int32 {
        128 + number
    }

    var label: String {
        switch self {
        case .interrupt: "SIGINT"
        case .termination: "SIGTERM"
        }
    }

    actor Recorder {
        private var signal: LearningCampaignProcessSignal?

        func record(_ signal: LearningCampaignProcessSignal) {
            self.signal = self.signal ?? signal
        }

        func receivedSignal() -> LearningCampaignProcessSignal? {
            signal
        }
    }
}
