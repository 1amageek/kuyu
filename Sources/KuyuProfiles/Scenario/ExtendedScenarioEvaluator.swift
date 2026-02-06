import KuyuCore

/// Evaluator that produces `ExtendedScenarioEvaluation` by combining the base
/// safety evaluation with control quality and inverse dynamics metrics.
public struct ExtendedScenarioEvaluator {
    public let baseEvaluator: ReferenceQuadrotorScenarioEvaluator

    public init(baseEvaluator: ReferenceQuadrotorScenarioEvaluator = ReferenceQuadrotorScenarioEvaluator()) {
        self.baseEvaluator = baseEvaluator
    }

    public func evaluate(
        definition: ReferenceQuadrotorScenarioDefinition,
        log: SimulationLog
    ) -> ExtendedScenarioEvaluation {
        let base = baseEvaluator.evaluate(definition: definition, log: log)
        let quality = computeControlQuality(log: log)
        let idm = computeInverseDynamics(log: log)
        return ExtendedScenarioEvaluation(
            base: base,
            controlQuality: quality,
            inverseDynamics: idm
        )
    }

    // MARK: - Control Quality Metrics

    private func computeControlQuality(log: SimulationLog) -> ControlQualityMetrics? {
        let events = log.events
        guard events.count > 1 else { return nil }

        let dt = log.timeStep.delta

        // Tracking error: use tilt angle as the error signal (target = 0 for hover)
        var sumSquaredError: Double = 0
        var maxError: Double = 0
        var count = 0

        for step in events {
            let tiltDeg = step.safetyTrace.tiltRadians * 180.0 / Double.pi
            sumSquaredError += tiltDeg * tiltDeg
            maxError = max(maxError, tiltDeg)
            count += 1
        }

        guard count > 0 else { return nil }

        let rms = (sumSquaredError / Double(count)).squareRoot()

        // Steady-state error: last 20% of the run
        let tailStart = max(0, events.count - events.count / 5)
        let tail = events[tailStart...]
        let steadyStateError: Double
        if tail.isEmpty {
            steadyStateError = rms
        } else {
            let tailSum = tail.reduce(0.0) { $0 + $1.safetyTrace.tiltRadians * 180.0 / Double.pi }
            steadyStateError = tailSum / Double(tail.count)
        }

        // Control effort: ∫|u|²dt
        var controlEffort: Double = 0
        for step in events {
            for actuator in step.actuatorValues {
                controlEffort += actuator.value * actuator.value * dt
            }
        }

        // Smoothness: ∫|du/dt|²dt
        var smoothness: Double = 0
        var prevValues: [Double] = events.first?.actuatorValues.map(\.value) ?? []
        for step in events.dropFirst() {
            let currentValues = step.actuatorValues.map(\.value)
            for (prev, curr) in zip(prevValues, currentValues) {
                let rate = (curr - prev) / dt
                smoothness += rate * rate * dt
            }
            prevValues = currentValues
        }

        // Settling time: first time tilt stays within 2% of 0° for 0.5s
        let settlingBand = 2.0 // degrees
        let settlingWindow = 0.5 // seconds
        var settlingTime: Double? = nil
        var windowStart: Double? = nil
        for step in events {
            let tiltDeg = step.safetyTrace.tiltRadians * 180.0 / Double.pi
            if tiltDeg <= settlingBand {
                windowStart = windowStart ?? step.time.time
                if let start = windowStart, step.time.time - start >= settlingWindow {
                    settlingTime = start
                    break
                }
            } else {
                windowStart = nil
            }
        }

        return ControlQualityMetrics(
            rmsTrackingError: rms,
            maxTrackingError: maxError,
            steadyStateError: steadyStateError,
            settlingTime: settlingTime,
            riseTime: nil,
            percentOvershoot: maxError > 0 ? maxError : nil,
            controlEffort: controlEffort,
            smoothness: smoothness
        )
    }

    // MARK: - Inverse Dynamics Validation

    private func computeInverseDynamics(log: SimulationLog) -> InverseDynamicsValidation? {
        let events = log.events
        guard events.count > 2 else { return nil }

        let dt = log.timeStep.delta

        // Simple IDM: compute required torques from angular acceleration,
        // compare with actual actuator outputs.
        var predictedSum: Double = 0
        var actualSum: Double = 0
        var crossSum: Double = 0
        var predictedSqSum: Double = 0
        var actualSqSum: Double = 0
        var mseSum: Double = 0
        var plausibleCount = 0
        var totalCount = 0

        var prevOmega = events[0].safetyTrace.omegaMagnitude

        for step in events.dropFirst() {
            let omega = step.safetyTrace.omegaMagnitude
            let angularAccel = (omega - prevOmega) / dt
            prevOmega = omega

            // Predicted control magnitude from angular acceleration
            let predicted = abs(angularAccel)

            // Actual control magnitude from actuator values
            let actuatorMag = step.actuatorValues.reduce(0.0) { $0 + $1.value * $1.value }.squareRoot()

            predictedSum += predicted
            actualSum += actuatorMag
            crossSum += predicted * actuatorMag
            predictedSqSum += predicted * predicted
            actualSqSum += actuatorMag * actuatorMag
            mseSum += (predicted - actuatorMag) * (predicted - actuatorMag)
            totalCount += 1

            // Plausibility: actuator values within expected range
            let allPlausible = step.actuatorValues.allSatisfy { $0.value.isFinite && $0.value >= 0 }
            if allPlausible { plausibleCount += 1 }
        }

        guard totalCount > 0 else { return nil }

        let n = Double(totalCount)
        let numerator = n * crossSum - predictedSum * actualSum
        let denomSq = (n * predictedSqSum - predictedSum * predictedSum) * (n * actualSqSum - actualSum * actualSum)
        let correlation: Double
        if denomSq > 0 {
            correlation = numerator / denomSq.squareRoot()
        } else {
            correlation = 0
        }

        return InverseDynamicsValidation(
            idmCorrelation: correlation,
            idmMSE: mseSum / n,
            physicallyPlausibleRatio: Double(plausibleCount) / n
        )
    }
}
