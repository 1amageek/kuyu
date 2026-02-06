import KuyuCore

public struct ReferenceQuadrotorScenarioEvaluator: ScenarioEvaluating {
    public init() {}

    public func evaluate(
        definition: ReferenceQuadrotorScenarioDefinition,
        log: SimulationLog
    ) -> ScenarioEvaluation {
        if (definition.kind == .liftHover || definition.kind == .singleLiftHover), let lift = definition.liftEnvelope {
            return evaluateLift(definition: definition, log: log, lift: lift)
        }

        let omegaLimit = definition.safetyEnvelope.omegaSafeMax
        let tiltLimitDeg = definition.safetyEnvelope.tiltSafeMaxDegrees
        let tiltLimitRad = tiltLimitDeg * Double.pi / 180.0
        let sustainedThreshold = definition.safetyEnvelope.sustainedViolationSeconds
        let groundZ = definition.safetyEnvelope.groundZ
        let fallDurationLimit = definition.safetyEnvelope.fallDurationSeconds
        let fallVelocityThreshold = definition.safetyEnvelope.fallVelocityThreshold
        let dt = log.timeStep.delta

        var maxOmega: Double = 0
        var maxTilt: Double = 0
        var currentViolation: Double = 0
        var maxViolation: Double = 0
        var fallDuration: Double = 0
        var groundViolated = false
        var fallViolated = false
        var failures: [String] = []
        let recovery = recoveryTime(definition: definition, log: log)
        let hfScore = hfStabilityScore(log: log)

        for step in log.events {
            let omega = step.safetyTrace.omegaMagnitude
            let tilt = step.safetyTrace.tiltRadians
            let altitude = step.plantState.root.position.z
            let verticalVelocity = step.plantState.root.velocity.z
            maxOmega = max(maxOmega, omega)
            maxTilt = max(maxTilt, tilt)

            if omega > omegaLimit || tilt > tiltLimitRad {
                currentViolation += dt
                maxViolation = max(maxViolation, currentViolation)
            } else {
                currentViolation = 0
            }

            if altitude < groundZ {
                groundViolated = true
            }

            if verticalVelocity < -fallVelocityThreshold {
                fallDuration += dt
                if fallDuration >= fallDurationLimit {
                    fallViolated = true
                }
            } else {
                fallDuration = 0
            }
        }

        if maxViolation >= sustainedThreshold {
            failures.append("sustained-violation")
        }
        if groundViolated {
            failures.append("ground-violation")
        }
        if fallViolated {
            failures.append("sustained-fall")
        }
        if let failureReason = log.failureReason, failures.contains(failureReason.rawValue) == false {
            failures.append(failureReason.rawValue)
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
        case .liftHover:
            break
        case .singleLiftHover:
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
            recoveryTimeSeconds: recovery,
            overshootDegrees: maxTiltDegrees,
            hfStabilityScore: hfScore,
            failures: failures,
            failureReason: log.failureReason,
            failureTime: log.failureTime
        )
    }

    private func evaluateLift(
        definition: ReferenceQuadrotorScenarioDefinition,
        log: SimulationLog,
        lift: LiftEnvelope
    ) -> ScenarioEvaluation {
        let groundZ = definition.safetyEnvelope.groundZ
        let fallDurationLimit = definition.safetyEnvelope.fallDurationSeconds
        let fallVelocityThreshold = definition.safetyEnvelope.fallVelocityThreshold
        let dt = log.timeStep.delta

        var maxAbsError: Double = 0
        var maxAbsVelocity: Double = 0
        var fallDuration: Double = 0
        var groundViolated = false
        var fallViolated = false
        var stableWindowStart: Double? = nil
        var hasStableWindow = false

        for step in log.events {
            let altitude = step.plantState.root.position.z
            let verticalVelocity = step.plantState.root.velocity.z
            let error = abs(altitude - lift.targetZ)
            let vel = abs(verticalVelocity)
            maxAbsError = max(maxAbsError, error)
            maxAbsVelocity = max(maxAbsVelocity, vel)

            if altitude < groundZ {
                groundViolated = true
            }

            if verticalVelocity < -fallVelocityThreshold {
                fallDuration += dt
                if fallDuration >= fallDurationLimit {
                    fallViolated = true
                }
            } else {
                fallDuration = 0
            }

            if step.time.time < lift.warmupTime {
                continue
            }

            if error <= lift.tolerance && vel <= lift.maxVelocity {
                stableWindowStart = stableWindowStart ?? step.time.time
                if let start = stableWindowStart, step.time.time - start >= lift.requiredHoldTime {
                    hasStableWindow = true
                    break
                }
            } else {
                stableWindowStart = nil
            }
        }

        var failures: [String] = []
        if groundViolated { failures.append("ground-violation") }
        if fallViolated { failures.append("sustained-fall") }
        if !hasStableWindow { failures.append("lift-unsettled") }
        if let failureReason = log.failureReason, failures.contains(failureReason.rawValue) == false {
            failures.append(failureReason.rawValue)
        }

        return ScenarioEvaluation(
            scenarioId: definition.config.id,
            seed: definition.config.seed,
            passed: failures.isEmpty,
            maxOmega: 0,
            maxTiltDegrees: 0,
            sustainedViolationSeconds: 0,
            recoveryTimeSeconds: nil,
            overshootDegrees: nil,
            hfStabilityScore: nil,
            failures: failures,
            failureReason: log.failureReason,
            failureTime: log.failureTime
        )
    }

    private func recoveryTime(definition: ReferenceQuadrotorScenarioDefinition, log: SimulationLog) -> Double? {
        let swapEvents = definition.swapEvents
        let hfEvents = definition.hfEvents
        guard !swapEvents.isEmpty || !hfEvents.isEmpty else { return nil }

        let endTimes: [Double] = swapEvents.flatMap { event in
            switch event {
            case .sensor(let sensor):
                return [sensor.startTime + sensor.duration]
            case .actuator(let actuator):
                return [actuator.startTime + actuator.duration]
            }
        } + hfEvents.map { $0.startTime + $0.duration }

        guard let lastEventEnd = endTimes.max() else { return nil }

        let omegaLimit = definition.safetyEnvelope.omegaSafeMax
        let tiltLimitRad = definition.safetyEnvelope.tiltSafeMaxDegrees * Double.pi / 180.0

        var windowStart: Double? = nil
        let requiredWindow = 0.5

        for step in log.events where step.time.time >= lastEventEnd {
            let omega = step.safetyTrace.omegaMagnitude
            let tilt = step.safetyTrace.tiltRadians
            if omega <= omegaLimit && tilt <= tiltLimitRad {
                windowStart = windowStart ?? step.time.time
                if let start = windowStart, step.time.time - start >= requiredWindow {
                    return start - lastEventEnd
                }
            } else {
                windowStart = nil
            }
        }

        return nil
    }

    private func hfStabilityScore(log: SimulationLog) -> Double? {
        guard log.events.count > 1 else { return nil }
        let dt = log.timeStep.delta
        var sum = 0.0
        var count = 0
        var lastOmega = log.events.first?.safetyTrace.omegaMagnitude ?? 0.0

        for step in log.events.dropFirst() {
            let omega = step.safetyTrace.omegaMagnitude
            let delta = abs(omega - lastOmega) / dt
            sum += delta
            count += 1
            lastOmega = omega
        }

        guard count > 0 else { return nil }
        let avg = sum / Double(count)
        return 1.0 / (1.0 + avg)
    }
}
