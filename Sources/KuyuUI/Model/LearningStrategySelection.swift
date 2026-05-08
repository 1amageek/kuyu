import Foundation

enum LearningStrategySelection: String, CaseIterable, Identifiable, Sendable {
    case reinforcementLearning = "RL"
    case geneticLearning = "GA"
    case hybrid = "Hybrid"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reinforcementLearning:
            return "強化学習 (RL)"
        case .geneticLearning:
            return "遺伝的学習 (GA)"
        case .hybrid:
            return "ハイブリッド"
        }
    }

    var description: String {
        switch self {
        case .reinforcementLearning:
            return "Backend protocol is defined, but standalone RL execution is not wired to this launcher yet."
        case .geneticLearning:
            return "Evolution support exists inside the hybrid campaign, but standalone GA launch is not exposed yet."
        case .hybrid:
            return "Runs the production campaign path: candidate search, regression evaluation, and artifact gate."
        }
    }

    var isExecutable: Bool {
        switch self {
        case .hybrid:
            return true
        case .reinforcementLearning, .geneticLearning:
            return false
        }
    }

    var availabilityLabel: String {
        isExecutable ? "available" : "planned"
    }

    var unavailableReason: String? {
        switch self {
        case .hybrid:
            return nil
        case .reinforcementLearning:
            return "Standalone RL is planned, but the shared learning campaign API currently executes the hybrid GA/RL harness."
        case .geneticLearning:
            return "Standalone GA is planned, but the shared learning campaign API currently executes GA through the hybrid harness."
        }
    }

    var systemImage: String {
        switch self {
        case .reinforcementLearning:
            return "brain.head.profile"
        case .geneticLearning:
            return "point.3.connected.trianglepath.dotted"
        case .hybrid:
            return "link"
        }
    }
}
