public protocol ActuatorEngine: Sendable {
    mutating func update(time: WorldTime) throws
    mutating func apply(commands: [ActuatorCommand], time: WorldTime) throws
}

