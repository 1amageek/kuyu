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
            return "テンプレート"
        case .environment:
            return "環境"
        case .strategy:
            return "学習戦略"
        case .launch:
            return "実行"
        }
    }

    var subtitle: String {
        switch self {
        case .template:
            return "Experiment の目的と初期条件"
        case .environment:
            return "Scenario と観測・実行条件"
        case .strategy:
            return "RL / GA / Hybrid の設計"
        case .launch:
            return "検証、見積もり、実行"
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
