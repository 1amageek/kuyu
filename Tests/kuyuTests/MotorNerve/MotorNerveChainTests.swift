import Testing
import KuyuPhysics
@testable import KuyuCore

@Test func motorNerveChainDirectMapsDriveToActuator() async throws {
    let contract = try makeContract(
        driveCount: 1,
        motorNerveSignals: [],
        motorNerveStages: [
            MotorNerveStageDefinition(
                id: "direct",
                type: .direct,
                inputs: ["drive0"],
                outputs: ["motor1"]
            )
        ],
        actuatorMax: 10.0
    )

    var chain = try MotorNerveChain(contract: contract)
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
    let contract = try makeContract(
        driveCount: 1,
        motorNerveSignals: ["mn0"],
        motorNerveStages: [
            MotorNerveStageDefinition(
                id: "stage-1",
                type: .direct,
                inputs: ["drive0"],
                outputs: ["mn0"]
            ),
            MotorNerveStageDefinition(
                id: "stage-2",
                type: .matrix,
                inputs: ["mn0"],
                outputs: ["motor1"],
                mapping: MotorNerveMapping(matrix: [[2.0]])
            )
        ],
        actuatorMax: 10.0
    )

    var chain = try MotorNerveChain(contract: contract)
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
    let contract = try makeContract(
        driveCount: 4,
        motorNerveSignals: [],
        motorNerveStages: [
            MotorNerveStageDefinition(
                id: "mixer",
                type: .mixer,
                inputs: ["drive0", "drive1", "drive2", "drive3"],
                outputs: ["motor1", "motor2", "motor3", "motor4"],
                parameters: ["layout": "quad-x"]
            )
        ],
        actuatorMax: 10.0
    )

    var chain = try MotorNerveChain(contract: contract)
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

private func makeContract(
    driveCount: Int,
    motorNerveSignals: [String],
    motorNerveStages: [MotorNerveStageDefinition],
    actuatorMax: Double
) throws -> EmbodimentContract {
    let driveSignals = (0..<driveCount).map { index in
        SignalDefinition(
            id: "drive\(index)",
            index: index,
            name: "drive\(index)",
            units: "norm",
            rateHz: 100.0,
            range: ScalarRange(min: 0.0, max: 1.0)
        )
    }
    let actuatorSignals = (0..<max(1, driveCount)).map { index in
        SignalDefinition(
            id: "motor\(index + 1)",
            index: index,
            name: "motor\(index + 1)",
            units: "N"
        )
    }
    let reflexSignals = (0..<driveCount).map { index in
        SignalDefinition(
            id: "reflex\(index)",
            index: index,
            name: "reflex\(index)",
            units: "norm"
        )
    }
    let motorSignals = motorNerveSignals.enumerated().map { idx, id in
        SignalDefinition(
            id: id,
            index: idx,
            name: id,
            units: "norm"
        )
    }

    let signals = SignalCatalog(
        sensor: [],
        actuator: actuatorSignals,
        drive: driveSignals,
        reflex: reflexSignals,
        motorNerve: motorSignals.isEmpty ? nil : motorSignals
    )

    let actuator = ActuatorDefinition(
        id: "actuator",
        type: "generic",
        channels: actuatorSignals.map(\.id),
        limits: ActuatorLimits(min: 0.0, max: actuatorMax, rateLimitPerSecond: 100.0)
    )

    let control = ControlContract(
        driveChannels: driveSignals.map(\.id),
        reflexChannels: reflexSignals.map(\.id),
        constraints: ControlConstraints(driveClamp: ScalarRange(min: 0.0, max: 1.0))
    )

    let contract = EmbodimentContract(
        schemaVersion: "kuyu.embodiment.v1",
        contractID: "test-contract",
        bodyID: "test-body",
        signals: signals,
        sensors: [],
        actuators: [actuator],
        control: control,
        motorNerve: MotorNerveContract(stages: motorNerveStages)
    )
    try contract.validate()
    return contract
}
