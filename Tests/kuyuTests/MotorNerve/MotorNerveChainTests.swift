import Testing
import KuyuProfiles
@testable import KuyuCore

@Test func motorNerveChainDirectMapsDriveToActuator() async throws {
    let descriptor = try makeDescriptor(
        driveCount: 1,
        motorNerveSignals: [],
        motorNerveStages: [
            RobotDescriptor.MotorNerveStage(
                id: "direct",
                type: .direct,
                inputs: ["drive0"],
                outputs: ["motor1"]
            )
        ],
        actuatorMax: 10.0
    )

    var chain = try MotorNerveChain(descriptor: descriptor)
    let drives = [try DriveIntent(index: DriveIndex(0), activation: 0.3)]
    let outputs = try chain.update(
        input: drives,
        corrections: [],
        telemetry: MotorNerveTelemetry(actuatorTelemetry: ActuatorTelemetrySnapshot(channels: [])),
        time: try WorldTime(stepIndex: 1, time: 0.01)
    )

    #expect(outputs.count == 1)
    #expect(abs(outputs[0].value - 0.3) < 1e-9)
}

@Test func motorNerveChainSupportsMultiStageRouting() async throws {
    let descriptor = try makeDescriptor(
        driveCount: 1,
        motorNerveSignals: ["mn0"],
        motorNerveStages: [
            RobotDescriptor.MotorNerveStage(
                id: "stage-1",
                type: .direct,
                inputs: ["drive0"],
                outputs: ["mn0"]
            ),
            RobotDescriptor.MotorNerveStage(
                id: "stage-2",
                type: .matrix,
                inputs: ["mn0"],
                outputs: ["motor1"],
                mapping: RobotDescriptor.MotorNerveMapping(matrix: [[2.0]])
            )
        ],
        actuatorMax: 10.0
    )

    var chain = try MotorNerveChain(descriptor: descriptor)
    let drives = [try DriveIntent(index: DriveIndex(0), activation: 0.4)]
    let outputs = try chain.update(
        input: drives,
        corrections: [],
        telemetry: MotorNerveTelemetry(actuatorTelemetry: ActuatorTelemetrySnapshot(channels: [])),
        time: try WorldTime(stepIndex: 2, time: 0.02)
    )

    #expect(outputs.count == 1)
    #expect(abs(outputs[0].value - 0.8) < 1e-9)
}

@Test func motorNerveChainMixerScalesByActuatorLimits() async throws {
    let descriptor = try makeDescriptor(
        driveCount: 4,
        motorNerveSignals: [],
        motorNerveStages: [
            RobotDescriptor.MotorNerveStage(
                id: "mixer",
                type: .mixer,
                inputs: ["drive0", "drive1", "drive2", "drive3"],
                outputs: ["motor1", "motor2", "motor3", "motor4"],
                parameters: ["layout": "quad-x"]
            )
        ],
        actuatorMax: 10.0
    )

    var chain = try MotorNerveChain(descriptor: descriptor)
    let drives = [
        try DriveIntent(index: DriveIndex(0), activation: 0.5),
        try DriveIntent(index: DriveIndex(1), activation: 0.0),
        try DriveIntent(index: DriveIndex(2), activation: 0.0),
        try DriveIntent(index: DriveIndex(3), activation: 0.0)
    ]
    let outputs = try chain.update(
        input: drives,
        corrections: [],
        telemetry: MotorNerveTelemetry(actuatorTelemetry: ActuatorTelemetrySnapshot(channels: [])),
        time: try WorldTime(stepIndex: 3, time: 0.03)
    )

    #expect(outputs.count == 4)
    for output in outputs {
        #expect(abs(output.value - 5.0) < 1e-9)
    }
}

private func makeDescriptor(
    driveCount: Int,
    motorNerveSignals: [String],
    motorNerveStages: [RobotDescriptor.MotorNerveStage],
    actuatorMax: Double
) throws -> RobotDescriptor {
    let driveSignals = (0..<driveCount).map { index in
        RobotDescriptor.SignalDefinition(
            id: "drive\(index)",
            index: index,
            name: "drive\(index)",
            units: "norm",
            rateHz: 100.0,
            range: RobotDescriptor.Range(min: 0.0, max: 1.0)
        )
    }
    let actuatorSignals = (0..<max(1, driveCount)).map { index in
        RobotDescriptor.SignalDefinition(
            id: "motor\(index + 1)",
            index: index,
            name: "motor\(index + 1)",
            units: "N"
        )
    }
    let reflexSignals = (0..<driveCount).map { index in
        RobotDescriptor.SignalDefinition(
            id: "reflex\(index)",
            index: index,
            name: "reflex\(index)",
            units: "norm"
        )
    }
    let motorSignals = motorNerveSignals.enumerated().map { idx, id in
        RobotDescriptor.SignalDefinition(
            id: id,
            index: idx,
            name: id,
            units: "norm"
        )
    }

    let signals = RobotDescriptor.Signals(
        sensor: [],
        actuator: actuatorSignals,
        drive: driveSignals,
        reflex: reflexSignals,
        motorNerve: motorSignals.isEmpty ? nil : motorSignals
    )

    let actuator = RobotDescriptor.ActuatorDefinition(
        id: "actuator",
        type: "generic",
        channels: actuatorSignals.map(\.id),
        limits: RobotDescriptor.ActuatorLimits(min: 0.0, max: actuatorMax, rateLimit: 100.0)
    )

    let control = RobotDescriptor.Control(
        driveChannels: driveSignals.map(\.id),
        reflexChannels: reflexSignals.map(\.id),
        constraints: RobotDescriptor.ControlConstraints(driveClamp: RobotDescriptor.Range(min: 0.0, max: 1.0))
    )

    return RobotDescriptor(
        robot: RobotDescriptor.Robot(robotID: "test", name: "test", category: "test"),
        physics: RobotDescriptor.Physics(
            model: RobotDescriptor.PhysicsModel(format: .urdf, path: "test.urdf"),
            engine: RobotDescriptor.EngineBinding(id: "test")
        ),
        signals: signals,
        sensors: [],
        actuators: [actuator],
        control: control,
        motorNerve: RobotDescriptor.MotorNerveDescriptor(stages: motorNerveStages)
    )
}
