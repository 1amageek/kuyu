public struct SafetyEnvelope: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case nonPositive(String)
    }

    public let omegaSafeMax: Double
    public let tiltSafeMaxDegrees: Double
    public let sustainedViolationSeconds: Double

    public init(
        omegaSafeMax: Double,
        tiltSafeMaxDegrees: Double,
        sustainedViolationSeconds: Double
    ) throws {
        guard omegaSafeMax.isFinite else { throw ValidationError.nonFinite("omegaSafeMax") }
        guard tiltSafeMaxDegrees.isFinite else { throw ValidationError.nonFinite("tiltSafeMaxDegrees") }
        guard sustainedViolationSeconds.isFinite else { throw ValidationError.nonFinite("sustainedViolationSeconds") }

        guard omegaSafeMax > 0 else { throw ValidationError.nonPositive("omegaSafeMax") }
        guard tiltSafeMaxDegrees > 0 else { throw ValidationError.nonPositive("tiltSafeMaxDegrees") }
        guard sustainedViolationSeconds > 0 else { throw ValidationError.nonPositive("sustainedViolationSeconds") }

        self.omegaSafeMax = omegaSafeMax
        self.tiltSafeMaxDegrees = tiltSafeMaxDegrees
        self.sustainedViolationSeconds = sustainedViolationSeconds
    }
}
