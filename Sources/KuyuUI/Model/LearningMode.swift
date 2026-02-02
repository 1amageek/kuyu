import Foundation

enum LearningMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case mlxAffine = "MLX Affine"
    case mlxMLP = "MLX MLP"

    var id: String { rawValue }

    var isEnabled: Bool {
        switch self {
        case .off:
            return false
        case .mlxAffine, .mlxMLP:
            return true
        }
    }
}
