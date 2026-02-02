public struct QuadrotorActuatorEngine: ActuatorEngine {
    public enum ActuatorError: Error, Equatable {
        case invalidIndex
        case missingCommands
    }

    public var parameters: QuadrotorParameters
    public var store: WorldStore
    public var timeStep: TimeStep
    public var motorMaxThrusts: MotorMaxThrusts
    private var commanded: MotorThrusts

    public init(
        parameters: QuadrotorParameters,
        store: WorldStore,
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

    public mutating func apply(commands: [ActuatorCommand], time: WorldTime) throws {
        guard commands.count >= 4 else { throw ActuatorError.missingCommands }

        var mapped: [UInt32: Double] = [:]
        for command in commands {
            let idx = command.index.rawValue
            guard idx < 4 else { throw ActuatorError.invalidIndex }
            mapped[idx] = clamp(command.value, index: idx)
        }

        guard mapped.count == 4 else { throw ActuatorError.missingCommands }

        commanded = try MotorThrusts(
            f1: mapped[0] ?? 0,
            f2: mapped[1] ?? 0,
            f3: mapped[2] ?? 0,
            f4: mapped[3] ?? 0
        )
    }

    private func clamp(_ value: Double, index: UInt32) -> Double {
        let maxValue = motorMaxThrusts.max(forIndex: index)
        return min(max(value, 0), maxValue)
    }
}
