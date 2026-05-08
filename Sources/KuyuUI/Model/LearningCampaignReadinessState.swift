import Foundation

struct LearningCampaignReadinessState: Sendable, Equatable {
    enum Status: String, Sendable {
        case idle
        case ready
        case blocked

        var label: String {
            switch self {
            case .idle:
                return "not checked"
            case .ready:
                return "ready"
            case .blocked:
                return "blocked"
            }
        }
    }

    var status: Status
    var message: String
    var checkedAt: Date?

    static let idle = LearningCampaignReadinessState(
        status: .idle,
        message: "Run dry validation before launching.",
        checkedAt: nil
    )

    static func ready(message: String) -> LearningCampaignReadinessState {
        LearningCampaignReadinessState(status: .ready, message: message, checkedAt: Date())
    }

    static func blocked(message: String) -> LearningCampaignReadinessState {
        LearningCampaignReadinessState(status: .blocked, message: message, checkedAt: Date())
    }
}
