import Foundation

public extension RobotDescriptor {
    enum ValidationError: Error, Equatable {
        case empty(String)
        case duplicateSignalId(String)
        case duplicateSignalIndex(String)
        case unknownSignalRef(String)
        case invalidRange(String)
        case nonFinite(String)
        case invalidMotorNerveMapping(String)
        case invalidPhysicsFormat(String)
    }

    func validate() throws {
        try validateRobot()
        try validatePhysics()
        let signalIndex = try validateSignals()
        try validateSensors(signals: signalIndex)
        try validateActuators(signals: signalIndex)
        try validateControl(signals: signalIndex)
        try validateMotorNerve(signals: signalIndex)
    }

    private func validateRobot() throws {
        if robot.robotID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.empty("robot.robotID")
        }
        if robot.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.empty("robot.name")
        }
        if robot.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.empty("robot.category")
        }
    }

    private func validatePhysics() throws {
        if physics.model.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.empty("physics.model.path")
        }
        if physics.engine.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.empty("physics.engine.id")
        }
        if physics.model.format != .urdf {
            throw ValidationError.invalidPhysicsFormat("physics.model.format")
        }
    }

    private func validateSignals() throws -> SignalIndex {
        let motorNerveSignals = signals.motorNerve ?? []
        let allSignals = signals.sensor + signals.actuator + signals.drive + signals.reflex + motorNerveSignals
        var idSet: Set<String> = []
        for signal in allSignals {
            if signal.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError.empty("signals.id")
            }
            if !idSet.insert(signal.id).inserted {
                throw ValidationError.duplicateSignalId(signal.id)
            }
            if signal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError.empty("signals.name")
            }
            if signal.units.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError.empty("signals.units")
            }
            if signal.index < 0 {
                throw ValidationError.invalidRange("signals.index")
            }
            if let rate = signal.rateHz {
                try ensureFinite(rate, "signals.rateHz")
            }
            if let range = signal.range {
                try validateRange(range, field: "signals.range")
            }
        }

        try validateSignalIndices(signals.sensor, label: "sensor")
        try validateSignalIndices(signals.actuator, label: "actuator")
        try validateSignalIndices(signals.drive, label: "drive")
        try validateSignalIndices(signals.reflex, label: "reflex")
        if !motorNerveSignals.isEmpty {
            try validateSignalIndices(motorNerveSignals, label: "motorNerve")
        }

        return SignalIndex(
            all: idSet,
            sensor: Set(signals.sensor.map { $0.id }),
            actuator: Set(signals.actuator.map { $0.id }),
            drive: Set(signals.drive.map { $0.id }),
            reflex: Set(signals.reflex.map { $0.id }),
            motorNerve: Set(motorNerveSignals.map { $0.id })
        )
    }

    private func validateSensors(signals: SignalIndex) throws {
        for sensor in sensors {
            if sensor.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError.empty("sensors.id")
            }
            if sensor.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError.empty("sensors.type")
            }
            if sensor.channels.isEmpty {
                throw ValidationError.invalidRange("sensors.channels")
            }
            for channel in sensor.channels {
                if !signals.sensor.contains(channel) {
                    throw ValidationError.unknownSignalRef(channel)
                }
            }
            try ensureFinite(sensor.rateHz, "sensors.rateHz")
            if sensor.rateHz <= 0 {
                throw ValidationError.invalidRange("sensors.rateHz")
            }
            try ensureFinite(sensor.latencyMs, "sensors.latencyMs")
            if sensor.latencyMs < 0 {
                throw ValidationError.invalidRange("sensors.latencyMs")
            }
            if let noise = sensor.noise {
                try ensureFinite(noise.bias, "sensors.noise.bias")
                try ensureFinite(noise.std, "sensors.noise.std")
                try ensureFinite(noise.randomWalkStd, "sensors.noise.randomWalkStd")
            }
            if let dropout = sensor.dropout {
                try ensureFinite(dropout.prob, "sensors.dropout.prob")
                try ensureFinite(dropout.burstMs, "sensors.dropout.burstMs")
            }
            if let swap = sensor.swapProfile {
                try validateRange(swap.gainRange, field: "sensors.swapProfile.gainRange")
                try validateRange(swap.biasRange, field: "sensors.swapProfile.biasRange")
                try validateRange(swap.delayMsRange, field: "sensors.swapProfile.delayMsRange")
            }
        }
    }

    private func validateActuators(signals: SignalIndex) throws {
        for actuator in actuators {
            if actuator.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError.empty("actuators.id")
            }
            if actuator.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError.empty("actuators.type")
            }
            if actuator.channels.isEmpty {
                throw ValidationError.invalidRange("actuators.channels")
            }
            for channel in actuator.channels {
                if !signals.actuator.contains(channel) {
                    throw ValidationError.unknownSignalRef(channel)
                }
            }
            try ensureFinite(actuator.limits.min, "actuators.limits.min")
            try ensureFinite(actuator.limits.max, "actuators.limits.max")
            try ensureFinite(actuator.limits.rateLimit, "actuators.limits.rateLimit")
            if actuator.limits.min > actuator.limits.max {
                throw ValidationError.invalidRange("actuators.limits")
            }
            if let dynamics = actuator.dynamics {
                try ensureFinite(dynamics.timeConstant, "actuators.dynamics.timeConstant")
                try ensureFinite(dynamics.deadzone, "actuators.dynamics.deadzone")
            }
            if let swap = actuator.swapProfile {
                try validateRange(swap.gainRange, field: "actuators.swapProfile.gainRange")
                try validateRange(swap.maxRange, field: "actuators.swapProfile.maxRange")
                try validateRange(swap.lagMsRange, field: "actuators.swapProfile.lagMsRange")
            }
        }
    }

    private func validateControl(signals: SignalIndex) throws {
        if control.driveChannels.isEmpty {
            throw ValidationError.invalidRange("control.driveChannels")
        }
        if control.reflexChannels.isEmpty {
            throw ValidationError.invalidRange("control.reflexChannels")
        }
        for channel in control.driveChannels {
            if !signals.drive.contains(channel) {
                throw ValidationError.unknownSignalRef(channel)
            }
        }
        for channel in control.reflexChannels {
            if !signals.reflex.contains(channel) {
                throw ValidationError.unknownSignalRef(channel)
            }
        }
        if let constraints = control.constraints {
            if let range = constraints.driveClamp {
                try validateRange(range, field: "control.constraints.driveClamp")
            }
            if let range = constraints.reflexClamp {
                try validateRange(range, field: "control.constraints.reflexClamp")
            }
        }
    }

    private func validateMotorNerve(signals: SignalIndex) throws {
        if motorNerve.stages.isEmpty {
            throw ValidationError.invalidMotorNerveMapping("stages-empty")
        }

        var stageIds: Set<String> = []
        var availableMotorNerveSignals: Set<String> = []
        var producedActuators: Set<String> = []
        var producedOutputs: Set<String> = []
        let motorNerveSignalIds = signals.motorNerve

        for stage in motorNerve.stages {
            if stage.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError.empty("motorNerve.stages.id")
            }
            if !stageIds.insert(stage.id).inserted {
                throw ValidationError.invalidMotorNerveMapping("duplicate-stage-id:\(stage.id)")
            }
            if stage.inputs.isEmpty {
                throw ValidationError.invalidMotorNerveMapping("stage-inputs-empty:\(stage.id)")
            }
            if stage.outputs.isEmpty {
                throw ValidationError.invalidMotorNerveMapping("stage-outputs-empty:\(stage.id)")
            }

            for input in stage.inputs {
                if signals.drive.contains(input) {
                    continue
                }
                if motorNerveSignalIds.contains(input) {
                    if !availableMotorNerveSignals.contains(input) {
                        throw ValidationError.invalidMotorNerveMapping("motorNerve-input-not-produced:\(input)")
                    }
                    continue
                }
                throw ValidationError.unknownSignalRef(input)
            }

            for output in stage.outputs {
                if signals.actuator.contains(output) {
                    if !producedOutputs.insert(output).inserted {
                        throw ValidationError.invalidMotorNerveMapping("duplicate-output:\(output)")
                    }
                    producedActuators.insert(output)
                    continue
                }
                if motorNerveSignalIds.contains(output) {
                    if !producedOutputs.insert(output).inserted {
                        throw ValidationError.invalidMotorNerveMapping("duplicate-output:\(output)")
                    }
                    availableMotorNerveSignals.insert(output)
                    continue
                }
                throw ValidationError.unknownSignalRef(output)
            }

            try validateMotorNerveStage(stage)
        }

        if motorNerveSignalIds.isEmpty && !availableMotorNerveSignals.isEmpty {
            throw ValidationError.invalidMotorNerveMapping("motorNerve-signals-missing")
        }

        let requiredActuators = signals.actuator
        if !requiredActuators.isEmpty && producedActuators != requiredActuators {
            throw ValidationError.invalidMotorNerveMapping("actuator-outputs-incomplete")
        }

        let motorNerveInputs = Set(
            motorNerve.stages.flatMap { $0.inputs }.filter { motorNerveSignalIds.contains($0) }
        )
        let motorNerveOutputs = Set(
            motorNerve.stages.flatMap { $0.outputs }.filter { motorNerveSignalIds.contains($0) }
        )
        if !motorNerveOutputs.isEmpty && !motorNerveOutputs.subtracting(motorNerveInputs).isEmpty {
            throw ValidationError.invalidMotorNerveMapping("motorNerve-output-not-consumed")
        }
    }

    private func validateMotorNerveStage(_ stage: MotorNerveStage) throws {
        switch stage.type {
        case .direct:
            if stage.inputs.count != stage.outputs.count {
                throw ValidationError.invalidMotorNerveMapping("direct input/output count mismatch")
            }
        case .matrix:
            guard let mapping = stage.mapping, let matrix = mapping.matrix else {
                throw ValidationError.invalidMotorNerveMapping("matrix mapping missing")
            }
            if matrix.count != stage.outputs.count {
                throw ValidationError.invalidMotorNerveMapping("matrix rows != outputs")
            }
            for row in matrix {
                if row.count != stage.inputs.count {
                    throw ValidationError.invalidMotorNerveMapping("matrix columns != inputs")
                }
                for value in row {
                    try ensureFinite(value, "motorNerve.mapping.matrix")
                }
            }
            if let bias = mapping.bias {
                if bias.count != stage.outputs.count {
                    throw ValidationError.invalidMotorNerveMapping("bias length != outputs")
                }
                for value in bias {
                    try ensureFinite(value, "motorNerve.mapping.bias")
                }
            }
            if let clip = mapping.clip {
                try validateRange(clip, field: "motorNerve.mapping.clip")
            }
        case .mixer:
            break
        case .custom:
            break
        }
    }

    private func validateSignalIndices(_ list: [SignalDefinition], label: String) throws {
        var indexSet: Set<Int> = []
        for signal in list {
            if !indexSet.insert(signal.index).inserted {
                throw ValidationError.duplicateSignalIndex("\(label):\(signal.index)")
            }
        }
    }

    private func validateRange(_ range: Range, field: String) throws {
        try ensureFinite(range.min, field)
        try ensureFinite(range.max, field)
        if range.min > range.max {
            throw ValidationError.invalidRange(field)
        }
    }

    private func ensureFinite(_ value: Double, _ field: String) throws {
        if !value.isFinite {
            throw ValidationError.nonFinite(field)
        }
    }

    private struct SignalIndex {
        let all: Set<String>
        let sensor: Set<String>
        let actuator: Set<String>
        let drive: Set<String>
        let reflex: Set<String>
        let motorNerve: Set<String>
    }
}
