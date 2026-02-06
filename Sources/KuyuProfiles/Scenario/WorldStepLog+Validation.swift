import KuyuCore

public extension WorldStepLog {
    var hasNonFinite: Bool {
        if !time.time.isFinite { return true }
        if !safetyTrace.omegaMagnitude.isFinite || !safetyTrace.tiltRadians.isFinite { return true }
        if !plantState.root.position.isFinite ||
            !plantState.root.velocity.isFinite ||
            !plantState.root.angularVelocity.isFinite ||
            !plantState.root.orientation.isFinite {
            return true
        }
        for sample in sensorSamples {
            if !sample.value.isFinite || !sample.timestamp.isFinite {
                return true
            }
        }
        for command in actuatorValues {
            if !command.value.isFinite {
                return true
            }
        }
        if let motorNerveTrace {
            for value in motorNerveTrace.uRaw + motorNerveTrace.uSat + motorNerveTrace.uRate + motorNerveTrace.uOut {
                if !value.isFinite {
                    return true
                }
            }
        }
        return false
    }
}
