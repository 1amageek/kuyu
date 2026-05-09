public enum BoundedWindowID: String, CaseIterable, Sendable {
    case main = "bounded.main"
    case welcome = "bounded.welcome"
    case simulation = "bounded.simulation"
    case monitor = "bounded.monitor"
    case analysis = "bounded.analysis"
    case report = "bounded.report"

    public var title: String {
        switch self {
        case .main: return "Bounded"
        case .welcome: return "Welcome to Bounded"
        case .simulation: return "Simulation"
        case .monitor: return "Monitor"
        case .analysis: return "Analysis"
        case .report: return "Report"
        }
    }

    public var systemImage: String {
        switch self {
        case .main: return "b.square"
        case .welcome: return "doc.badge.plus"
        case .simulation: return "play.rectangle"
        case .monitor: return "chart.line.uptrend.xyaxis"
        case .analysis: return "tablecells"
        case .report: return "doc.richtext"
        }
    }
}
