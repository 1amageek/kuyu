import KuyuCore

public extension DeterminismConfig {
    static let tier1Baseline: DeterminismConfig = {
        do {
            return try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
        } catch {
            preconditionFailure("Invalid Tier1 baseline config: \(error)")
        }
    }()
}
