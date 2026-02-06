public enum FailureReason: String, Sendable, Codable, Equatable {
    case simulationIntegrity = "simulation-integrity"
    case groundViolation = "ground-violation"
    case sustainedFall = "sustained-fall"
    case safetyEnvelope = "safety-envelope"
}

public struct FailureEvent: Sendable, Codable, Equatable {
    public let reason: FailureReason
    public let time: Double

    public init(reason: FailureReason, time: Double) {
        self.reason = reason
        self.time = time
    }
}
