public struct ScenarioEvaluator {
    public init() {}

    public func evaluate(
        definition: ScenarioDefinition,
        log: SimulationLog
    ) -> ScenarioEvaluation {
        let omegaLimit = definition.safetyEnvelope.omegaSafeMax
        let tiltLimitDeg = definition.safetyEnvelope.tiltSafeMaxDegrees
        let tiltLimitRad = tiltLimitDeg * Double.pi / 180.0
        let sustainedThreshold = definition.safetyEnvelope.sustainedViolationSeconds
        let dt = log.timeStep.delta

        var maxOmega: Double = 0
        var maxTilt: Double = 0
        var currentViolation: Double = 0
        var maxViolation: Double = 0
        var failures: [String] = []

        for step in log.events {
            let omega = step.safetyTrace.omegaMagnitude
            let tilt = step.safetyTrace.tiltRadians
            maxOmega = max(maxOmega, omega)
            maxTilt = max(maxTilt, tilt)

            if omega > omegaLimit || tilt > tiltLimitRad {
                currentViolation += dt
                maxViolation = max(maxViolation, currentViolation)
            } else {
                currentViolation = 0
            }
        }

        if maxViolation >= sustainedThreshold {
            failures.append("sustained-violation")
        }

        switch definition.kind {
        case .hoverStart:
            let limit = 5.0
            let start = 3.0
            if log.events.contains(where: { $0.time.time >= start && $0.safetyTrace.omegaMagnitude > limit }) {
                failures.append("hover-start-omega")
            }
        case .impulseTorqueShock:
            if let event = definition.torqueEvents.first {
                let targetTime = event.startTime + event.duration + 2.0
                if let sample = log.events.first(where: { $0.time.time >= targetTime }) {
                    let tiltDegrees = sample.safetyTrace.tiltRadians * 180.0 / Double.pi
                    if tiltDegrees > 20.0 {
                        failures.append("impulse-tilt-recovery")
                    }
                }
            }
        case .sustainedWindTorque:
            if maxOmega > omegaLimit {
                failures.append("sustained-omega-exceeded")
            }
        case .sensorDriftStress:
            break
        case .actuatorDegradation:
            break
        }

        let maxTiltDegrees = maxTilt * 180.0 / Double.pi
        return ScenarioEvaluation(
            scenarioId: definition.config.id,
            seed: definition.config.seed,
            passed: failures.isEmpty,
            maxOmega: maxOmega,
            maxTiltDegrees: maxTiltDegrees,
            sustainedViolationSeconds: maxViolation,
            failures: failures
        )
    }
}
