public struct SimulationSchedule: Sendable, Codable, Equatable {
    public let sensor: SubsystemSchedule
    public let actuator: SubsystemSchedule
    public let cut: SubsystemSchedule
    public let motorNerve: SubsystemSchedule?

    public init(
        sensor: SubsystemSchedule,
        actuator: SubsystemSchedule,
        cut: SubsystemSchedule,
        motorNerve: SubsystemSchedule? = nil
    ) {
        self.sensor = sensor
        self.actuator = actuator
        self.cut = cut
        self.motorNerve = motorNerve
    }
}

