public enum BoundedWindowID: String, CaseIterable, Sendable {
    case simulation = "bounded.simulation"
    case monitor = "bounded.monitor"
    case analysis = "bounded.analysis"
    case report = "bounded.report"

    public var title: String {
        switch self {
        case .simulation: return "シミュレーション"
        case .monitor: return "モニター"
        case .analysis: return "分析"
        case .report: return "レポート"
        }
    }

    public var systemImage: String {
        switch self {
        case .simulation: return "play.rectangle"
        case .monitor: return "chart.line.uptrend.xyaxis"
        case .analysis: return "tablecells"
        case .report: return "doc.richtext"
        }
    }
}
