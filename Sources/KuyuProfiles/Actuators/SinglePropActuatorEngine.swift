import KuyuCore

public struct SinglePropActuatorEngine: ActuatorEngine {
    public enum ActuatorError: Error, Equatable {
        case missingCommand
        case invalidIndex
    }

    public var maxThrust: Double
    public var motorTimeConstant: Double
    public var store: ReferenceQuadrotorWorldStore
    public var timeStep: TimeStep

    private var commanded: Double

    public init(
        maxThrust: Double,
        motorTimeConstant: Double,
        store: ReferenceQuadrotorWorldStore,
        timeStep: TimeStep
    ) {
        self.maxThrust = maxThrust
        self.motorTimeConstant = motorTimeConstant
        self.store = store
        self.timeStep = timeStep
        self.commanded = store.motorThrusts.f1
    }

    public mutating func update(time: WorldTime) throws {
        let dt = timeStep.delta
        let tau = max(motorTimeConstant, 1e-6)
        let next = store.motorThrusts.f1 + (commanded - store.motorThrusts.f1) * (dt / tau)
        store.motorThrusts = try MotorThrusts(
            f1: clamp(next),
            f2: 0.0,
            f3: 0.0,
            f4: 0.0
        )
    }

    public mutating func apply(values: [ActuatorValue], time: WorldTime) throws {
        _ = time
        guard let value = values.first(where: { $0.index.rawValue == 0 }) else {
            throw ActuatorError.missingCommand
        }
        guard value.index.rawValue == 0 else { throw ActuatorError.invalidIndex }
        commanded = clamp(value.value)
    }

    public func telemetrySnapshot() -> ActuatorTelemetrySnapshot {
        ActuatorTelemetrySnapshot(
            channels: [
                ActuatorChannelSnapshot(id: "motor1", value: store.motorThrusts.f1, units: "N")
            ]
        )
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), maxThrust)
    }
}
