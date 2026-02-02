import kuyu

enum DeterminismSelection: String, CaseIterable, Identifiable {
    case tier0 = "Tier0 (Bitwise)"
    case tier1 = "Tier1 (Epsilon)"
    case tier2 = "Tier2 (Statistical)"

    var id: String { rawValue }

    func makeConfig() throws -> DeterminismConfig {
        switch self {
        case .tier0:
            return try DeterminismConfig(tier: .tier0)
        case .tier1:
            return .tier1Baseline
        case .tier2:
            return try DeterminismConfig(tier: .tier2)
        }
    }
}
