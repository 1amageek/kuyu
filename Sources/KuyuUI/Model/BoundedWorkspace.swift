import SwiftUI

public enum BoundedWorkspace: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case runs
    case experimentDesign
    case reinforcementLearning
    case geneticLearning
    case hybridIntegration
    case environment
    case settings
    case system

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .runs: return "Runs"
        case .experimentDesign: return "Experiment Design"
        case .reinforcementLearning: return "Reinforcement Learning"
        case .geneticLearning: return "Genetic Learning"
        case .hybridIntegration: return "Hybrid Integration"
        case .environment: return "Environment"
        case .settings: return "Settings"
        case .system: return "System"
        }
    }

    public var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .runs: return "list.bullet.rectangle"
        case .experimentDesign: return "doc.badge.gearshape"
        case .reinforcementLearning: return "flask"
        case .geneticLearning: return "point.3.connected.trianglepath.dotted"
        case .hybridIntegration: return "arrow.triangle.merge"
        case .environment: return "cube.transparent"
        case .settings: return "gearshape"
        case .system: return "desktopcomputer"
        }
    }

    var isTrainingWorkspace: Bool {
        switch self {
        case .experimentDesign, .reinforcementLearning, .geneticLearning, .hybridIntegration, .environment:
            return true
        case .dashboard, .runs, .settings, .system:
            return false
        }
    }
}
