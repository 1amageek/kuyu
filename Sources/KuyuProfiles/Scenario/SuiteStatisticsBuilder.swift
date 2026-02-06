import KuyuCore

/// Builds suite-level robustness statistics from a collection of extended evaluations.
public struct SuiteStatisticsBuilder {
    public init() {}

    public func build(evaluations: [ExtendedScenarioEvaluation]) -> RobustnessStatistics {
        guard !evaluations.isEmpty else {
            return RobustnessStatistics(
                passRate: 0,
                meanRecoveryTime: nil,
                worstCaseOmega: 0,
                worstCaseTilt: 0,
                consistencyScore: 0,
                degradationMargin: 0
            )
        }

        let bases = evaluations.map(\.base)
        let count = Double(bases.count)

        // Pass rate
        let passCount = bases.filter(\.passed).count
        let passRate = Double(passCount) / count

        // Recovery time statistics
        let recoveryTimes = bases.compactMap(\.recoveryTimeSeconds)
        let meanRecoveryTime: Double?
        if recoveryTimes.isEmpty {
            meanRecoveryTime = nil
        } else {
            meanRecoveryTime = recoveryTimes.reduce(0.0, +) / Double(recoveryTimes.count)
        }

        // Worst-case metrics
        let worstCaseOmega = bases.map(\.maxOmega).max() ?? 0
        let worstCaseTilt = bases.map(\.maxTiltDegrees).max() ?? 0

        // Consistency score: 1 - coefficient of variation of maxOmega
        let omegas = bases.map(\.maxOmega)
        let consistencyScore = coefficientOfVariationScore(omegas)

        // Degradation margin: compare stressed vs unstressed scenarios
        let degradationMargin = computeDegradationMargin(evaluations: bases)

        return RobustnessStatistics(
            passRate: passRate,
            meanRecoveryTime: meanRecoveryTime,
            worstCaseOmega: worstCaseOmega,
            worstCaseTilt: worstCaseTilt,
            consistencyScore: consistencyScore,
            degradationMargin: degradationMargin
        )
    }

    // MARK: - Private

    private func coefficientOfVariationScore(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 1.0 }
        let n = Double(values.count)
        let mean = values.reduce(0.0, +) / n
        guard mean > 0 else { return 1.0 }
        let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / n
        let cv = variance.squareRoot() / mean
        return max(0.0, 1.0 - cv)
    }

    private func computeDegradationMargin(evaluations: [ScenarioEvaluation]) -> Double {
        // Compare mean maxOmega of first half (assumed baseline) vs second half (assumed stressed)
        guard evaluations.count >= 2 else { return 0 }
        let mid = evaluations.count / 2
        let baselineOmega = evaluations[..<mid].map(\.maxOmega)
        let stressedOmega = evaluations[mid...].map(\.maxOmega)

        let baselineMean = baselineOmega.reduce(0.0, +) / Double(baselineOmega.count)
        let stressedMean = stressedOmega.reduce(0.0, +) / Double(stressedOmega.count)

        guard baselineMean > 0 else { return 0 }
        return max(0.0, (stressedMean - baselineMean) / baselineMean)
    }
}
