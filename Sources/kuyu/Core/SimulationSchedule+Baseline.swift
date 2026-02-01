public extension SimulationSchedule {
    static func baseline(cutPeriodSteps: UInt64 = 2) throws -> SimulationSchedule {
        try SimulationSchedule(
            sensor: SubsystemSchedule(periodSteps: 1),
            actuator: SubsystemSchedule(periodSteps: 1),
            cut: SubsystemSchedule(periodSteps: cutPeriodSteps),
            externalDal: nil
        )
    }
}
