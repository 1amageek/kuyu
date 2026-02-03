public struct SimulationSchedule: Sendable, Codable, Equatable {
    public let sensor: SubsystemSchedule
    public let actuator: SubsystemSchedule
    public let cut: SubsystemSchedule
    public let externalDal: SubsystemSchedule?

    public init(
        sensor: SubsystemSchedule,
        actuator: SubsystemSchedule,
        cut: SubsystemSchedule,
        externalDal: SubsystemSchedule? = nil
    ) {
        self.sensor = sensor
        self.actuator = actuator
        self.cut = cut
        self.externalDal = externalDal
    }
}

