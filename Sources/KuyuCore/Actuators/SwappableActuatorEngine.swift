public struct SwappableActuatorEngine<Engine: ActuatorEngine>: ActuatorEngine {
    public var engine: Engine
    public let baseMaxThrusts: MotorMaxThrusts
    public let swapEvents: [SwapEvent]
    public let hfEvents: [HFStressEvent]

    private var lastCommands: [UInt32: Double]

    public init(
        engine: Engine,
        baseMaxThrusts: MotorMaxThrusts,
        swapEvents: [SwapEvent],
        hfEvents: [HFStressEvent]
    ) {
        self.engine = engine
        self.baseMaxThrusts = baseMaxThrusts
        self.swapEvents = swapEvents
        self.hfEvents = hfEvents
        self.lastCommands = [:]
    }

    public mutating func update(time: WorldTime) throws {
        try engine.update(time: time)
    }

    public mutating func apply(commands: [ActuatorCommand], time: WorldTime) throws {
        let adjusted = try applySwaps(commands: commands, time: time)
        try engine.apply(commands: adjusted, time: time)
    }

    private mutating func applySwaps(commands: [ActuatorCommand], time: WorldTime) throws -> [ActuatorCommand] {
        let modifiers = modifiersForTime(time)
        var output: [ActuatorCommand] = []
        output.reserveCapacity(commands.count)

        for command in commands {
            let index = command.index.rawValue
            let mod = modifiers[index] ?? Modifiers()
            let baseMax = baseMaxThrusts.max(forIndex: index)
            let maxOutput = baseMax * mod.maxOutputScale

            var value = command.value * mod.gainScale
            if abs(value) < mod.deadzoneShift {
                value = 0
            }

            let previous = lastCommands[index] ?? value
            if mod.lagScale > 1 {
                let factor = 1.0 / mod.lagScale
                value = previous + (value - previous) * factor
            }

            value = min(max(value, 0), maxOutput)
            lastCommands[index] = value
            output.append(try ActuatorCommand(index: command.index, value: value))
        }

        return output
    }

    private func modifiersForTime(_ time: WorldTime) -> [UInt32: Modifiers] {
        var modifiers: [UInt32: Modifiers] = [:]
        let now = time.time

        for event in swapEvents {
            guard case .actuator(let swap) = event else { continue }
            guard now >= swap.startTime && now <= swap.startTime + swap.duration else { continue }
            var entry = modifiers[swap.motorIndex] ?? Modifiers()
            entry.gainScale *= swap.gainScale
            entry.lagScale *= swap.lagScale
            entry.maxOutputScale *= swap.maxOutputScale
            entry.deadzoneShift = max(entry.deadzoneShift, abs(swap.deadzoneShift))
            modifiers[swap.motorIndex] = entry
        }

        for event in hfEvents {
            guard now >= event.startTime && now <= event.startTime + event.duration else { continue }
            switch event.kind {
            case .actuatorSaturation:
                let scale = max(0.0, min(1.0, event.magnitude))
                for idx in 0..<4 {
                    var entry = modifiers[UInt32(idx)] ?? Modifiers()
                    entry.maxOutputScale = min(entry.maxOutputScale, scale)
                    modifiers[UInt32(idx)] = entry
                }
            default:
                break
            }
        }

        return modifiers
    }

    private struct Modifiers {
        var gainScale: Double = 1.0
        var lagScale: Double = 1.0
        var maxOutputScale: Double = 1.0
        var deadzoneShift: Double = 0.0
    }
}
