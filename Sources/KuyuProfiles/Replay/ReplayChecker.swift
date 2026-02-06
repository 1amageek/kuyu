import simd
import KuyuCore

public struct ReplayChecker {
    public enum ReplayError: Error, Equatable {
        case tierMismatch
        case tier1ToleranceMissing
        case logShapeMismatch
    }

    public init() {}

    public func check(reference: SimulationLog, candidate: SimulationLog) throws -> ReplayCheckResult {
        guard reference.determinism.tier == candidate.determinism.tier else {
            throw ReplayError.tierMismatch
        }

        switch reference.determinism.tier {
        case .tier0:
            return checkTier0(reference: reference, candidate: candidate)
        case .tier1:
            return try checkTier1(reference: reference, candidate: candidate)
        case .tier2:
            return ReplayCheckResult(
                scenarioId: candidate.scenarioId,
                seed: candidate.seed,
                tier: .tier2,
                passed: false,
                issues: ["tier2-not-supported"],
                residuals: .zero
            )
        }
    }

    private func checkTier0(reference: SimulationLog, candidate: SimulationLog) -> ReplayCheckResult {
        let passed = reference == candidate
        return ReplayCheckResult(
            scenarioId: candidate.scenarioId,
            seed: candidate.seed,
            tier: .tier0,
            passed: passed,
            issues: passed ? [] : ["log-mismatch"],
            residuals: .zero
        )
    }

    private func checkTier1(reference: SimulationLog, candidate: SimulationLog) throws -> ReplayCheckResult {
        guard let tolerance = reference.determinism.tier1Tolerance else {
            throw ReplayError.tier1ToleranceMissing
        }

        var issues: [String] = []
        if reference.scenarioId != candidate.scenarioId { issues.append("scenario-id-mismatch") }
        if reference.seed != candidate.seed { issues.append("seed-mismatch") }
        if reference.timeStep != candidate.timeStep { issues.append("time-step-mismatch") }
        if reference.configHash != candidate.configHash { issues.append("config-hash-mismatch") }
        if reference.events.count != candidate.events.count {
            throw ReplayError.logShapeMismatch
        }

        var maxPosition: Double = 0
        var maxVelocity: Double = 0
        var maxAngularVelocity: Double = 0
        var maxQuatResidual: Double = 0
        var maxActuatorTelemetry: Double = 0
        var maxSensor: Double = 0

        for (refStep, candStep) in zip(reference.events, candidate.events) {
            if refStep.time != candStep.time {
                issues.append("time-mismatch")
            }
            if refStep.events != candStep.events {
                issues.append("event-order-mismatch")
            }
            if refStep.disturbances.torqueBody != candStep.disturbances.torqueBody {
                issues.append("disturbance-torque-mismatch")
            }
            if refStep.disturbances.forceWorld != candStep.disturbances.forceWorld {
                issues.append("disturbance-force-mismatch")
            }

            let refRoot = refStep.plantState.root
            let candRoot = candStep.plantState.root
            let pResidual = simd_length(refRoot.position.simd - candRoot.position.simd)
            let vResidual = simd_length(refRoot.velocity.simd - candRoot.velocity.simd)
            let wResidual = simd_length(refRoot.angularVelocity.simd - candRoot.angularVelocity.simd)
            let qDot = abs(refRoot.orientation.dot(candRoot.orientation))
            let qResidual = 1.0 - min(1.0, qDot)

            maxPosition = max(maxPosition, pResidual)
            maxVelocity = max(maxVelocity, vResidual)
            maxAngularVelocity = max(maxAngularVelocity, wResidual)
            maxQuatResidual = max(maxQuatResidual, qResidual)

            maxActuatorTelemetry = max(
                maxActuatorTelemetry,
                maxTelemetryResidual(ref: refStep.actuatorTelemetry, cand: candStep.actuatorTelemetry)
            )
            maxSensor = max(maxSensor, maxSensorResidual(ref: refStep.sensorSamples, cand: candStep.sensorSamples))

            if refStep.actuatorValues.count != candStep.actuatorValues.count {
                issues.append("actuator-command-count-mismatch")
            } else if !refStep.actuatorValues.isEmpty {
                let commandResidual = maxCommandResidual(ref: refStep.actuatorValues, cand: candStep.actuatorValues)
                if commandResidual > tolerance.motorThrust {
                    issues.append("actuator-command-residual")
                }
            }
        }

        if maxPosition > tolerance.position { issues.append("position-residual") }
        if maxVelocity > tolerance.velocity { issues.append("velocity-residual") }
        if maxAngularVelocity > tolerance.angularVelocity { issues.append("angular-velocity-residual") }
        if maxQuatResidual > tolerance.quaternionResidual { issues.append("quaternion-residual") }
        if maxActuatorTelemetry > tolerance.motorThrust { issues.append("motor-thrust-residual") }
        if maxSensor > tolerance.sensor { issues.append("sensor-residual") }

        let residuals = ReplayResiduals(
            position: maxPosition,
            velocity: maxVelocity,
            angularVelocity: maxAngularVelocity,
            quaternionResidual: maxQuatResidual,
            motorThrust: maxActuatorTelemetry,
            sensor: maxSensor
        )

        return ReplayCheckResult(
            scenarioId: candidate.scenarioId,
            seed: candidate.seed,
            tier: .tier1,
            passed: issues.isEmpty,
            issues: issues,
            residuals: residuals
        )
    }

    private func maxTelemetryResidual(
        ref: ActuatorTelemetrySnapshot,
        cand: ActuatorTelemetrySnapshot
    ) -> Double {
        let refMap = Dictionary(uniqueKeysWithValues: ref.channels.map { ($0.id, $0.value) })
        let candMap = Dictionary(uniqueKeysWithValues: cand.channels.map { ($0.id, $0.value) })
        guard refMap.keys == candMap.keys else { return Double.infinity }
        var maxResidual: Double = 0
        for (key, refValue) in refMap {
            guard let candValue = candMap[key] else { return Double.infinity }
            maxResidual = max(maxResidual, abs(refValue - candValue))
        }
        return maxResidual
    }

    private func maxSensorResidual(ref: [ChannelSample], cand: [ChannelSample]) -> Double {
        guard ref.count == cand.count else { return Double.infinity }
        var maxResidual: Double = 0
        for (lhs, rhs) in zip(ref, cand) {
            if lhs.channelIndex != rhs.channelIndex { return Double.infinity }
            if lhs.timestamp != rhs.timestamp { return Double.infinity }
            maxResidual = max(maxResidual, abs(lhs.value - rhs.value))
        }
        return maxResidual
    }

    private func maxCommandResidual(ref: [ActuatorValue], cand: [ActuatorValue]) -> Double {
        guard ref.count == cand.count else { return Double.infinity }
        var maxResidual: Double = 0
        for (lhs, rhs) in zip(ref, cand) {
            if lhs.index != rhs.index { return Double.infinity }
            maxResidual = max(maxResidual, abs(lhs.value - rhs.value))
        }
        return maxResidual
    }
}
