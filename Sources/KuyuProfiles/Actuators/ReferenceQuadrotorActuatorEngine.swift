import KuyuCore

public struct ReferenceQuadrotorActuatorEngine: ActuatorEngine {
    public enum ActuatorError: Error, Equatable {
        case invalidIndex
        case missingCommands
    }

    public var parameters: ReferenceQuadrotorParameters
    public var store: ReferenceQuadrotorWorldStore
    public var timeStep: TimeStep
    public var motorMaxThrusts: MotorMaxThrusts
    private var commanded: MotorThrusts

    public init(
        parameters: ReferenceQuadrotorParameters,
        store: ReferenceQuadrotorWorldStore,
        timeStep: TimeStep,
        motorMaxThrusts: MotorMaxThrusts? = nil
    ) {
        self.parameters = parameters
        self.store = store
        self.timeStep = timeStep
        if let motorMaxThrusts {
            self.motorMaxThrusts = motorMaxThrusts
        } else {
            do {
                self.motorMaxThrusts = try MotorMaxThrusts.uniform(parameters.maxThrust)
            } catch {
                preconditionFailure("Invalid motor max thrusts for parameters.maxThrust=\(parameters.maxThrust)")
            }
        }
        self.commanded = store.motorThrusts
    }

    public mutating func update(time: WorldTime) throws {
        let dt = timeStep.delta
        let tau = parameters.motorTimeConstant

        let f1 = store.motorThrusts.f1 + (commanded.f1 - store.motorThrusts.f1) * (dt / tau)
        let f2 = store.motorThrusts.f2 + (commanded.f2 - store.motorThrusts.f2) * (dt / tau)
        let f3 = store.motorThrusts.f3 + (commanded.f3 - store.motorThrusts.f3) * (dt / tau)
        let f4 = store.motorThrusts.f4 + (commanded.f4 - store.motorThrusts.f4) * (dt / tau)

        store.motorThrusts = try MotorThrusts(
            f1: clamp(f1, index: 0),
            f2: clamp(f2, index: 1),
            f3: clamp(f3, index: 2),
            f4: clamp(f4, index: 3)
        )
    }

    public mutating func apply(values: [ActuatorValue], time: WorldTime) throws {
        guard values.count >= 4 else { throw ActuatorError.missingCommands }

        var mapped: [UInt32: Double] = [:]
        for value in values {
            let idx = value.index.rawValue
            guard idx < 4 else { throw ActuatorError.invalidIndex }
            mapped[idx] = clamp(value.value, index: idx)
        }

        guard mapped.count == 4 else { throw ActuatorError.missingCommands }

        commanded = try MotorThrusts(
            f1: mapped[0] ?? 0,
            f2: mapped[1] ?? 0,
            f3: mapped[2] ?? 0,
            f4: mapped[3] ?? 0
        )
    }

    public func telemetrySnapshot() -> ActuatorTelemetrySnapshot {
        ActuatorTelemetrySnapshot(
            channels: [
                ActuatorChannelSnapshot(id: "motor1", value: store.motorThrusts.f1, units: "N"),
                ActuatorChannelSnapshot(id: "motor2", value: store.motorThrusts.f2, units: "N"),
                ActuatorChannelSnapshot(id: "motor3", value: store.motorThrusts.f3, units: "N"),
                ActuatorChannelSnapshot(id: "motor4", value: store.motorThrusts.f4, units: "N")
            ]
        )
    }

    private func clamp(_ value: Double, index: UInt32) -> Double {
        let maxValue = motorMaxThrusts.max(forIndex: index)
        return min(max(value, 0), maxValue)
    }
}
