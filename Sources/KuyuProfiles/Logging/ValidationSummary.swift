import KuyuCore

public struct EvaluationAggregate: Sendable, Codable, Equatable {
    public let averageRecoveryTime: Double?
    public let worstOvershootDegrees: Double?
    public let averageHfStabilityScore: Double?

    public init(
        averageRecoveryTime: Double?,
        worstOvershootDegrees: Double?,
        averageHfStabilityScore: Double?
    ) {
        self.averageRecoveryTime = averageRecoveryTime
        self.worstOvershootDegrees = worstOvershootDegrees
        self.averageHfStabilityScore = averageHfStabilityScore
    }

    public static func from(evaluations: [ScenarioEvaluation]) -> EvaluationAggregate {
        let recoveryValues = evaluations.compactMap { $0.recoveryTimeSeconds }
        let overshootValues = evaluations.compactMap { $0.overshootDegrees }
        let hfValues = evaluations.compactMap { $0.hfStabilityScore }

        let averageRecovery = recoveryValues.isEmpty ? nil : recoveryValues.reduce(0, +) / Double(recoveryValues.count)
        let worstOvershoot = overshootValues.max()
        let averageHf = hfValues.isEmpty ? nil : hfValues.reduce(0, +) / Double(hfValues.count)

        return EvaluationAggregate(
            averageRecoveryTime: averageRecovery,
            worstOvershootDegrees: worstOvershoot,
            averageHfStabilityScore: averageHf
        )
    }
}

public struct ValidationSummary: Sendable, Codable, Equatable {
    public let suitePassed: Bool
    public let evaluations: [ScenarioEvaluation]
    public let replayChecks: [ReplayCheckResult]
    public let manifest: [ReferenceQuadrotorScenarioManifest]
    public let aggregate: EvaluationAggregate

    private enum CodingKeys: String, CodingKey {
        case suitePassed
        case evaluations
        case replayChecks
        case manifest
        case aggregate
    }

    public init(
        suitePassed: Bool,
        evaluations: [ScenarioEvaluation],
        replayChecks: [ReplayCheckResult],
        manifest: [ReferenceQuadrotorScenarioManifest],
        aggregate: EvaluationAggregate
    ) {
        self.suitePassed = suitePassed
        self.evaluations = evaluations
        self.replayChecks = replayChecks
        self.manifest = manifest
        self.aggregate = aggregate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        suitePassed = try container.decode(Bool.self, forKey: .suitePassed)
        evaluations = try container.decode([ScenarioEvaluation].self, forKey: .evaluations)
        replayChecks = try container.decode([ReplayCheckResult].self, forKey: .replayChecks)
        manifest = try container.decode([ReferenceQuadrotorScenarioManifest].self, forKey: .manifest)
        aggregate = try container.decodeIfPresent(EvaluationAggregate.self, forKey: .aggregate)
            ?? EvaluationAggregate.from(evaluations: evaluations)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(suitePassed, forKey: .suitePassed)
        try container.encode(evaluations, forKey: .evaluations)
        try container.encode(replayChecks, forKey: .replayChecks)
        try container.encode(manifest, forKey: .manifest)
        try container.encode(aggregate, forKey: .aggregate)
    }
}
