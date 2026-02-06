import KuyuCore

public struct SafetyFailurePolicy: FailurePolicy {
    public let envelope: SafetyEnvelope
    public let timeStep: Double
    private var safetyViolationDuration: Double = 0
    private var fallDuration: Double = 0

    public init(envelope: SafetyEnvelope, timeStep: Double) {
        self.envelope = envelope
        self.timeStep = timeStep
    }

    public mutating func update(log: WorldStepLog) -> FailureEvent? {
        if log.hasNonFinite {
            return FailureEvent(reason: .simulationIntegrity, time: log.time.time)
        }

        let omegaLimit = envelope.omegaSafeMax
        let tiltLimit = envelope.tiltSafeMaxDegrees * Double.pi / 180.0
        let omega = log.safetyTrace.omegaMagnitude
        let tilt = log.safetyTrace.tiltRadians

        if omega > omegaLimit || tilt > tiltLimit {
            safetyViolationDuration += timeStep
            if safetyViolationDuration >= envelope.sustainedViolationSeconds {
                return FailureEvent(reason: .safetyEnvelope, time: log.time.time)
            }
        } else {
            safetyViolationDuration = 0
        }

        let altitude = log.plantState.root.position.z
        if altitude < envelope.groundZ {
            return FailureEvent(reason: .groundViolation, time: log.time.time)
        }

        let verticalVelocity = log.plantState.root.velocity.z
        if verticalVelocity < -envelope.fallVelocityThreshold {
            fallDuration += timeStep
            if fallDuration >= envelope.fallDurationSeconds {
                return FailureEvent(reason: .sustainedFall, time: log.time.time)
            }
        } else {
            fallDuration = 0
        }

        return nil
    }
}
