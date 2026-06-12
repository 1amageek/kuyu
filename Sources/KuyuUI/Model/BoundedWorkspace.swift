import SwiftUI

public enum BoundedWorkspace: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case design
    case run
    case results
    case system

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .design: return "Design"
        case .run: return "Run"
        case .results: return "Results"
        case .system: return "System"
        }
    }

    public var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .design: return "doc.badge.gearshape"
        case .run: return "paperplane"
        case .results: return "tablecells"
        case .system: return "desktopcomputer"
        }
    }

    var showsPhaseStepper: Bool {
        self == .design
    }
}
