import KuyuCore

public struct SafetyEnvelope: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case nonPositive(String)
    }

    public let omegaSafeMax: Double
    public let tiltSafeMaxDegrees: Double
    public let sustainedViolationSeconds: Double
    public let groundZ: Double
    public let fallDurationSeconds: Double
    public let fallVelocityThreshold: Double

    public init(
        omegaSafeMax: Double,
        tiltSafeMaxDegrees: Double,
        sustainedViolationSeconds: Double,
        groundZ: Double,
        fallDurationSeconds: Double,
        fallVelocityThreshold: Double
    ) throws {
        guard omegaSafeMax.isFinite else { throw ValidationError.nonFinite("omegaSafeMax") }
        guard tiltSafeMaxDegrees.isFinite else { throw ValidationError.nonFinite("tiltSafeMaxDegrees") }
        guard sustainedViolationSeconds.isFinite else { throw ValidationError.nonFinite("sustainedViolationSeconds") }
        guard groundZ.isFinite else { throw ValidationError.nonFinite("groundZ") }
        guard fallDurationSeconds.isFinite else { throw ValidationError.nonFinite("fallDurationSeconds") }
        guard fallVelocityThreshold.isFinite else { throw ValidationError.nonFinite("fallVelocityThreshold") }

        guard omegaSafeMax > 0 else { throw ValidationError.nonPositive("omegaSafeMax") }
        guard tiltSafeMaxDegrees > 0 else { throw ValidationError.nonPositive("tiltSafeMaxDegrees") }
        guard sustainedViolationSeconds > 0 else { throw ValidationError.nonPositive("sustainedViolationSeconds") }
        guard fallDurationSeconds > 0 else { throw ValidationError.nonPositive("fallDurationSeconds") }
        guard fallVelocityThreshold >= 0 else { throw ValidationError.nonPositive("fallVelocityThreshold") }

        self.omegaSafeMax = omegaSafeMax
        self.tiltSafeMaxDegrees = tiltSafeMaxDegrees
        self.sustainedViolationSeconds = sustainedViolationSeconds
        self.groundZ = groundZ
        self.fallDurationSeconds = fallDurationSeconds
        self.fallVelocityThreshold = fallVelocityThreshold
    }
}
