import Foundation

enum RobotProfileSelection: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case quadrotor = "Quadrotor"
    case generic = "Generic"

    var id: String { rawValue }
}
