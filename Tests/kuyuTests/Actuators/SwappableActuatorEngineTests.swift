import Testing
import KuyuProfiles
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func swappableActuatorClampsMaxOutput() async throws {
    let baseMax = try MotorMaxThrusts.uniform(10.0)
    let swap = try ActuatorSwapEvent(
        kind: .maxOutputShift,
        startTime: 0.0,
        duration: 1.0,
        motorIndex: 0,
        gainScale: 1.0,
        lagScale: 1.0,
        maxOutputScale: 0.5,
        deadzoneShift: 0.0
    )

    var engine = SwappableActuatorEngine(
        engine: RecordingActuatorEngine(),
        baseMaxThrusts: baseMax,
        swapEvents: [.actuator(swap)],
        hfEvents: []
    )

    let values = [try ActuatorValue(index: ActuatorIndex(0), value: 9.0)]
    try engine.apply(values: values, time: try WorldTime(stepIndex: 1, time: 0.001))

    let recorded = engine.engine.lastValues.first { $0.index.rawValue == 0 }?.value ?? 0
    #expect(abs(recorded - 5.0) < 1e-6)
}

private struct RecordingActuatorEngine: ActuatorEngine {
    var lastValues: [ActuatorValue] = []

    mutating func update(time: WorldTime) throws {}

    mutating func apply(values: [ActuatorValue], time: WorldTime) throws {
        lastValues = values
    }

    func telemetrySnapshot() -> ActuatorTelemetrySnapshot {
        ActuatorTelemetrySnapshot(channels: [])
    }
}
