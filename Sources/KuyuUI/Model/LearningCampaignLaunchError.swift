import Foundation

public enum LearningCampaignLaunchError: Error, Sendable, Equatable, LocalizedError {
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return reason
        }
    }
}
