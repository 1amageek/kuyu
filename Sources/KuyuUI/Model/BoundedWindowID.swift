public enum BoundedWindowID: String, CaseIterable, Sendable {
    case simulation = "bounded.simulation"

    public var title: String {
        switch self {
        case .simulation: return "シミュレーション"
        }
    }

    public var systemImage: String {
        switch self {
        case .simulation: return "play.rectangle"
        }
    }
}
