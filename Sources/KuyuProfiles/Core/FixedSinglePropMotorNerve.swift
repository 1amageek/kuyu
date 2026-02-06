import Foundation
import KuyuCore

public struct FixedSinglePropMotorNerve: MotorNerveEndpoint, MotorNerveTraceProvider {
    public struct Config: Sendable, Equatable {
        public let maxThrust: Double
        public let rateLimitPerSecond: Double
        public let smoothingTimeConstant: Double?
        public let baseThrottle: Double

        public init(
            maxThrust: Double,
            rateLimitPerSecond: Double = 2.0,
            smoothingTimeConstant: Double? = 0.08,
            baseThrottle: Double = 0.0
        ) {
            self.maxThrust = maxThrust
            self.rateLimitPerSecond = rateLimitPerSecond
            self.smoothingTimeConstant = smoothingTimeConstant
            self.baseThrottle = min(max(baseThrottle, 0.0), 1.0)
        }
    }

    public var lastTrace: MotorNerveTrace? { lastTraceStorage }

    private let config: Config
    private var lastOutput: Double
    private var lastFiltered: Double
    private var lastTime: Double?
    private var lastTraceStorage: MotorNerveTrace?

    public init(config: Config) {
        self.config = config
        self.lastOutput = 0.0
        self.lastFiltered = 0.0
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
        let driveThrottle = clamp(driveValue(index: 0, from: adjusted), lower: 0.0, upper: 1.0)
        let throttle = clamp(config.baseThrottle + driveThrottle, lower: 0.0, upper: 1.0)

        let uRaw = [throttle]
        let uSat = [clamp(throttle, lower: 0.0, upper: 1.0)]

        let dt = max(0.0, time.time - (lastTime ?? time.time))
        let uRate = [applyRateLimit(value: uSat[0], dt: dt)]
        let uOut = [applySmoothing(value: uRate[0], dt: dt)]
        let finalOut = telemetry.failsafeActive ? [0.0] : uOut

        lastTime = time.time
        lastOutput = finalOut[0]
        lastFiltered = finalOut[0]
        lastTraceStorage = MotorNerveTrace(
            uRaw: uRaw,
            uSat: uSat,
            uRate: uRate,
            uOut: finalOut,
            failsafeActive: telemetry.failsafeActive
        )

        let scaled = finalOut[0] * config.maxThrust
        return [try ActuatorValue(index: ActuatorIndex(0), value: scaled)]
    }

    private func driveValue(index: UInt32, from drives: [DriveIntent]) -> Double {
        drives.first(where: { $0.index.rawValue == index })?.activation ?? 0.0
    }

    private func applyRateLimit(value: Double, dt: Double) -> Double {
        guard dt > 0.0, config.rateLimitPerSecond > 0.0 else { return value }
        let maxDelta = config.rateLimitPerSecond * dt
        let delta = value - lastOutput
        let limited = clamp(delta, lower: -maxDelta, upper: maxDelta)
        return lastOutput + limited
    }

    private func applySmoothing(value: Double, dt: Double) -> Double {
        guard let tau = config.smoothingTimeConstant, tau > 0.0, dt > 0.0 else { return value }
        let alpha = exp(-dt / tau)
        return alpha * lastFiltered + (1.0 - alpha) * value
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
