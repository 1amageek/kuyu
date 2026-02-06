import KuyuCore

public struct LiftMotorNerve: MotorNerveEndpoint {
    public let motorMaxThrusts: MotorMaxThrusts

    public init(motorMaxThrusts: MotorMaxThrusts) {
        self.motorMaxThrusts = motorMaxThrusts
    }

    public mutating func update(
        input drives: [DriveIntent],
        corrections: [ReflexCorrection],
        telemetry: MotorNerveTelemetry,
        time: WorldTime
    ) throws -> [ActuatorValue] {
        _ = telemetry
        _ = time
        let adjusted = try applyCorrections(drives: drives, corrections: corrections)
        let throttle = adjusted.first(where: { $0.index.rawValue == 0 })?.activation ?? 0.0
        let clamped = clamp(throttle, lower: 0.0, upper: 1.0)
        var commands: [ActuatorValue] = []
        commands.reserveCapacity(4)
        let scaled = [
            clamped * motorMaxThrusts.f1,
            clamped * motorMaxThrusts.f2,
            clamped * motorMaxThrusts.f3,
            clamped * motorMaxThrusts.f4
        ]
        for (index, value) in scaled.enumerated() {
            let actuatorIndex = ActuatorIndex(UInt32(index))
            let command = try ActuatorValue(index: actuatorIndex, value: value)
            commands.append(command)
        }
        return commands
    }

    private func applyCorrections(
        drives: [DriveIntent],
        corrections: [ReflexCorrection]
    ) throws -> [DriveIntent] {
        guard !corrections.isEmpty else { return drives }

        var aggregate: [DriveIndex: ReflexAggregate] = [:]
        for correction in corrections {
            var entry = aggregate[correction.driveIndex] ?? ReflexAggregate()
            entry.clampMultiplier *= correction.clampMultiplier
            entry.damping = min(1.0, entry.damping + correction.damping)
            entry.delta += correction.delta
            aggregate[correction.driveIndex] = entry
        }

        return try drives.map { drive in
            guard let entry = aggregate[drive.index] else { return drive }
            let damped = drive.activation * (1.0 - entry.damping)
            let clamped = damped * entry.clampMultiplier
            let adjusted = clamped + entry.delta
            return try DriveIntent(index: drive.index, activation: adjusted)
        }
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private struct ReflexAggregate {
        var clampMultiplier: Double = 1.0
        var damping: Double = 0.0
        var delta: Double = 0.0
    }
}
