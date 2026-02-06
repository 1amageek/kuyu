import KuyuCore

public struct ActuatorDegradationEngine: ActuatorEngine {
    public enum DegradationError: Error, Equatable {
        case invalidMotorIndex
    }

    public var engine: ReferenceQuadrotorActuatorEngine
    public let degradation: ActuatorDegradation?
    private let baseMaxThrusts: MotorMaxThrusts

    public init(
        engine: ReferenceQuadrotorActuatorEngine,
        degradation: ActuatorDegradation?
    ) {
        self.engine = engine
        self.degradation = degradation
        self.baseMaxThrusts = engine.motorMaxThrusts
    }

    public mutating func update(time: WorldTime) throws {
        try applyDegradationIfNeeded(time: time)
        try engine.update(time: time)
    }

    public mutating func apply(values: [ActuatorValue], time: WorldTime) throws {
        try applyDegradationIfNeeded(time: time)
        try engine.apply(values: values, time: time)
    }

    public func telemetrySnapshot() -> ActuatorTelemetrySnapshot {
        engine.telemetrySnapshot()
    }

    private mutating func applyDegradationIfNeeded(time: WorldTime) throws {
        guard let degradation else {
            engine.motorMaxThrusts = baseMaxThrusts
            return
        }

        guard degradation.motorIndex < 4 else { throw DegradationError.invalidMotorIndex }

        if time.time >= degradation.startTime {
            let baseMax = baseMaxThrusts.max(forIndex: degradation.motorIndex)
            let scaled = baseMax * degradation.maxThrustScale
            engine.motorMaxThrusts = try baseMaxThrusts.setting(index: degradation.motorIndex, value: scaled)
        } else {
            engine.motorMaxThrusts = baseMaxThrusts
        }
    }
}
