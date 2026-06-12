public enum BoundedWindowID: String, CaseIterable, Sendable {
    case main = "bounded.main"
    case welcome = "bounded.welcome"
    case simulation = "bounded.simulation"
    case report = "bounded.report"

    public var title: String {
        switch self {
        case .main: return "Bounded"
        case .welcome: return "Welcome to Bounded"
        case .simulation: return "Simulation"
        case .report: return "Report"
        }
    }

    public var systemImage: String {
        switch self {
        case .main: return "b.square"
        case .welcome: return "doc.badge.plus"
        case .simulation: return "play.rectangle"
        case .report: return "doc.richtext"
        }
    }
}
