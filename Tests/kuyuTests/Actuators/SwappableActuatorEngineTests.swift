import Testing
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

    let commands = [try ActuatorCommand(index: ActuatorIndex(0), value: 9.0)]
    try engine.apply(commands: commands, time: try WorldTime(stepIndex: 1, time: 0.001))

    let recorded = engine.engine.lastCommands.first { $0.index.rawValue == 0 }?.value ?? 0
    #expect(abs(recorded - 5.0) < 1e-6)
}

private struct RecordingActuatorEngine: ActuatorEngine {
    var lastCommands: [ActuatorCommand] = []

    mutating func update(time: WorldTime) throws {}

    mutating func apply(commands: [ActuatorCommand], time: WorldTime) throws {
        lastCommands = commands
    }
}
