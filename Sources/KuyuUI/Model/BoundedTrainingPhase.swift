import SwiftUI

public enum BoundedTrainingPhase: String, CaseIterable, Identifiable, Sendable {
    case template
    case environment
    case strategy
    case launch

    public var id: String { rawValue }

    var step: Int {
        switch self {
        case .template:
            return 1
        case .environment:
            return 2
        case .strategy:
            return 3
        case .launch:
            return 4
        }
    }

    var title: String {
        switch self {
        case .template:
            return "Template"
        case .environment:
            return "Environment"
        case .strategy:
            return "Strategy"
        case .launch:
            return "Launch"
        }
    }

    var subtitle: String {
        switch self {
        case .template:
            return "Experiment objective and initial conditions"
        case .environment:
            return "Scenario, observation, and execution conditions"
        case .strategy:
            return "RL / GA / Hybrid design"
        case .launch:
            return "Validate, estimate, and run"
        }
    }

    var systemImage: String {
        switch self {
        case .template:
            return "cube"
        case .environment:
            return "square.grid.3x3"
        case .strategy:
            return "cpu"
        case .launch:
            return "paperplane"
        }
    }
}
