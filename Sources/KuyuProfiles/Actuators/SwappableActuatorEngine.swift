import KuyuCore

public struct SwappableActuatorEngine<Engine: ActuatorEngine>: ActuatorEngine {
    public var engine: Engine
    public let baseMaxThrusts: MotorMaxThrusts
    public let swapEvents: [SwapEvent]
    public let hfEvents: [HFStressEvent]

    private var lastValues: [UInt32: Double]

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
        self.lastValues = [:]
    }

    public mutating func update(time: WorldTime) throws {
        try engine.update(time: time)
    }

    public mutating func apply(values: [ActuatorValue], time: WorldTime) throws {
        let adjusted = try applySwaps(values: values, time: time)
        try engine.apply(values: adjusted, time: time)
    }

    public func telemetrySnapshot() -> ActuatorTelemetrySnapshot {
        engine.telemetrySnapshot()
    }

    private mutating func applySwaps(values: [ActuatorValue], time: WorldTime) throws -> [ActuatorValue] {
        let modifiers = modifiersForTime(time)
        var output: [ActuatorValue] = []
        output.reserveCapacity(values.count)

        for value in values {
            let index = value.index.rawValue
            let mod = modifiers[index] ?? Modifiers()
            let baseMax = baseMaxThrusts.max(forIndex: index)
            let maxOutput = baseMax * mod.maxOutputScale

            var updated = value.value * mod.gainScale
            if abs(updated) < mod.deadzoneShift {
                updated = 0
            }

            let previous = lastValues[index] ?? updated
            if mod.lagScale > 1 {
                let factor = 1.0 / mod.lagScale
                updated = previous + (updated - previous) * factor
            }

            updated = min(max(updated, 0), maxOutput)
            lastValues[index] = updated
            output.append(try ActuatorValue(index: value.index, value: updated))
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
