import Foundation
import KuyuCore

public struct FixedQuadMotorNerve: MotorNerveEndpoint, MotorNerveTraceProvider {
    public struct Config: Sendable, Equatable {
        public let mixer: ReferenceQuadrotorMixer
        public let motorMaxThrusts: MotorMaxThrusts
        public let rollScale: Double
        public let pitchScale: Double
        public let yawScale: Double
        public let rateLimitPerSecond: Double
        public let smoothingTimeConstant: Double?

        public init(
            mixer: ReferenceQuadrotorMixer,
            motorMaxThrusts: MotorMaxThrusts,
            rollScale: Double = 1.0,
            pitchScale: Double = 1.0,
            yawScale: Double = 1.0,
            rateLimitPerSecond: Double = 2.0,
            smoothingTimeConstant: Double? = 0.08
        ) {
            self.mixer = mixer
            self.motorMaxThrusts = motorMaxThrusts
            self.rollScale = rollScale
            self.pitchScale = pitchScale
            self.yawScale = yawScale
            self.rateLimitPerSecond = rateLimitPerSecond
            self.smoothingTimeConstant = smoothingTimeConstant
        }
    }

    public var lastTrace: MotorNerveTrace? { lastTraceStorage }

    private let config: Config
    private var lastOutput: [Double]
    private var lastFiltered: [Double]
    private var lastTime: Double?
    private var lastTraceStorage: MotorNerveTrace?

    public init(config: Config) {
        self.config = config
        self.lastOutput = [0.0, 0.0, 0.0, 0.0]
        self.lastFiltered = [0.0, 0.0, 0.0, 0.0]
        self.lastTime = nil
        self.lastTraceStorage = nil
    }

    public mutating func update(
        input drives: [DriveIntent],
        corrections: [ReflexCorrection],
        telemetry: MotorNerveTelemetry,
        time: WorldTime
    ) throws -> [ActuatorValue] {
        let adjusted = try applyCorrections(drives: drives, corrections: corrections)

        let throttle = clamp(driveValue(index: 0, from: adjusted), lower: 0.0, upper: 1.0)
        let roll = clamp(driveValue(index: 1, from: adjusted), lower: -1.0, upper: 1.0) * config.rollScale
        let pitch = clamp(driveValue(index: 2, from: adjusted), lower: -1.0, upper: 1.0) * config.pitchScale
        let yaw = clamp(driveValue(index: 3, from: adjusted), lower: -1.0, upper: 1.0) * config.yawScale

        let spin = config.mixer.spinDirections
        let uRaw = [
            throttle - pitch + spin.x * yaw,
            throttle + roll + spin.y * yaw,
            throttle + pitch + spin.z * yaw,
            throttle - roll + spin.w * yaw
        ]

        let uSat = uRaw.map { clamp($0, lower: 0.0, upper: 1.0) }

        let dt = max(0.0, time.time - (lastTime ?? time.time))
        let uRate = applyRateLimit(values: uSat, dt: dt)
        let uOut = applySmoothing(values: uRate, dt: dt)
        let finalOut = telemetry.failsafeActive ? [0.0, 0.0, 0.0, 0.0] : uOut

        lastTime = time.time
        lastOutput = finalOut
        lastFiltered = finalOut
        lastTraceStorage = MotorNerveTrace(
            uRaw: uRaw,
            uSat: uSat,
            uRate: uRate,
            uOut: finalOut,
            failsafeActive: telemetry.failsafeActive
        )

        return try makeCommands(values: finalOut)
    }

    private func driveValue(index: UInt32, from drives: [DriveIntent]) -> Double {
        drives.first(where: { $0.index.rawValue == index })?.activation ?? 0.0
    }

    private func applyRateLimit(values: [Double], dt: Double) -> [Double] {
        guard dt > 0.0, config.rateLimitPerSecond > 0.0 else { return values }
        let maxDelta = config.rateLimitPerSecond * dt
        return zip(values, lastOutput).map { current, previous in
            let delta = current - previous
            let limited = clamp(delta, lower: -maxDelta, upper: maxDelta)
            return previous + limited
        }
    }

    private func applySmoothing(values: [Double], dt: Double) -> [Double] {
        guard let tau = config.smoothingTimeConstant, tau > 0.0, dt > 0.0 else { return values }
        let alpha = exp(-dt / tau)
        return zip(values, lastFiltered).map { current, previous in
            alpha * previous + (1.0 - alpha) * current
        }
    }

    private func makeCommands(values: [Double]) throws -> [ActuatorValue] {
        let scaled = [
            values[0] * config.motorMaxThrusts.f1,
            values[1] * config.motorMaxThrusts.f2,
            values[2] * config.motorMaxThrusts.f3,
            values[3] * config.motorMaxThrusts.f4
        ]
        return try scaled.enumerated().map { index, value in
            try ActuatorValue(index: ActuatorIndex(UInt32(index)), value: value)
        }
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
