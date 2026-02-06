import KuyuCore

/// Automatic labeling of simulation runs based on evaluation results.
///
/// Converts raw evaluation metrics into categorical labels and quality scores
/// suitable for filtering, stratified sampling, and curriculum learning.
public struct AutoLabeler {

    public enum QualityLabel: String, Sendable, Codable, Equatable {
        case excellent
        case good
        case marginal
        case failed
    }

    public struct LabeledResult: Sendable, Equatable {
        public let quality: QualityLabel
        public let score: Double
        public let passed: Bool
        public let tags: [String]

        public init(quality: QualityLabel, score: Double, passed: Bool, tags: [String]) {
            self.quality = quality
            self.score = score
            self.passed = passed
            self.tags = tags
        }
    }

    public struct Thresholds: Sendable, Equatable {
        public let excellentMaxTilt: Double
        public let goodMaxTilt: Double
        public let marginalMaxTilt: Double
        public let excellentMaxOmega: Double
        public let goodMaxOmega: Double

        public init(
            excellentMaxTilt: Double = 5.0,
            goodMaxTilt: Double = 15.0,
            marginalMaxTilt: Double = 30.0,
            excellentMaxOmega: Double = 2.0,
            goodMaxOmega: Double = 8.0
        ) {
            self.excellentMaxTilt = excellentMaxTilt
            self.goodMaxTilt = goodMaxTilt
            self.marginalMaxTilt = marginalMaxTilt
            self.excellentMaxOmega = excellentMaxOmega
            self.goodMaxOmega = goodMaxOmega
        }
    }

    public let thresholds: Thresholds

    public init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    /// Label a single evaluation result.
    public func label(evaluation: ExtendedScenarioEvaluation) -> LabeledResult {
        let base = evaluation.base

        guard base.passed else {
            return LabeledResult(
                quality: .failed,
                score: 0,
                passed: false,
                tags: base.failures
            )
        }

        var tags: [String] = []
        let tilt = base.maxTiltDegrees
        let omega = base.maxOmega

        if let recovery = base.recoveryTimeSeconds {
            tags.append("recovery:\(String(format: "%.2f", recovery))s")
        }

        if let quality = evaluation.controlQuality {
            if quality.controlEffort > 0 {
                tags.append("effort:\(String(format: "%.1f", quality.controlEffort))")
            }
        }

        let quality: QualityLabel
        let score: Double

        if tilt <= thresholds.excellentMaxTilt && omega <= thresholds.excellentMaxOmega {
            quality = .excellent
            score = 1.0 - (tilt / thresholds.excellentMaxTilt) * 0.1
        } else if tilt <= thresholds.goodMaxTilt && omega <= thresholds.goodMaxOmega {
            quality = .good
            score = 0.7 - (tilt / thresholds.goodMaxTilt) * 0.1
        } else if tilt <= thresholds.marginalMaxTilt {
            quality = .marginal
            score = 0.4 - (tilt / thresholds.marginalMaxTilt) * 0.1
        } else {
            quality = .marginal
            score = 0.2
        }

        return LabeledResult(
            quality: quality,
            score: max(0, min(1, score)),
            passed: true,
            tags: tags
        )
    }

    /// Label a batch of evaluations.
    public func labelAll(evaluations: [ExtendedScenarioEvaluation]) -> [LabeledResult] {
        evaluations.map { label(evaluation: $0) }
    }
}
