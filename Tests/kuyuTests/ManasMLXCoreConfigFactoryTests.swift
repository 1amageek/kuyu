import Testing
@testable import KuyuMLX
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

@MainActor
@Test func coreConfigWithoutEmbodimentUsesUntypedMode() {
    let config = ManasMLXCoreConfigBuilder.makeConfig(
        inputSize: 12,
        driveCount: 4,
        auxEnabled: true,
        embodiment: nil
    )

    #expect(config.useSharedEncoder == false)
    #expect(config.useSharedDecoder == false)
    #expect(config.typeEmbeddingDim == 0)
    #expect(config.typeEmbeddingCount == 0)
    #expect(config.ascendingTypeIndices == nil)
    #expect(config.actuatorTypeIndices == nil)
}

@MainActor
@Test func coreConfigWithEmbodimentUsesSharedTypedMode() {
    let embodiment = makeEmbodiment(includeDescending: false)
    let config = ManasMLXCoreConfigBuilder.makeConfig(
        inputSize: 8,
        driveCount: 2,
        auxEnabled: false,
        embodiment: embodiment
    )

    #expect(config.useSharedEncoder == true)
    #expect(config.useSharedDecoder == true)
    #expect(config.typeEmbeddingDim == 16)
    #expect(config.typeEmbeddingCount == 6)
    #expect(config.ascendingTypeIndices == [0, 0, 1, 1, 2, 2, 3, 3])
    #expect(config.actuatorTypeIndices == [4, 5])
}

@MainActor
@Test func coreConfigWithDescendingChannelsSetsDescendingConfig() {
    let embodiment = makeEmbodiment(includeDescending: true)
    let config = ManasMLXCoreConfigBuilder.makeConfig(
        inputSize: 8,
        driveCount: 2,
        auxEnabled: false,
        embodiment: embodiment
    )

    #expect(config.descendingSize == 2)
    #expect(config.descendingEmbeddingSize == 16)
    #expect(config.descendingTypeIndices == [4, 5])
    #expect(config.actuatorTypeIndices == [6, 7])
    #expect(config.typeEmbeddingCount == 8)
}

private func makeEmbodiment(includeDescending: Bool) -> EmbodimentContract {
    let descendingSignals: [SignalDefinition]? = includeDescending ? [
        SignalDefinition(
            id: "intent.thrust",
            index: 0,
            name: "intent.thrust",
            units: "norm",
            group: "intent.thrust"
        ),
        SignalDefinition(
            id: "intent.yaw",
            index: 1,
            name: "intent.yaw",
            units: "norm",
            group: "intent.yaw"
        ),
    ] : nil

    let signals = SignalCatalog(
        sensor: [
            SignalDefinition(id: "imu.ax", index: 0, name: "imu.ax", units: "m/s2"),
            SignalDefinition(id: "imu.ay", index: 1, name: "imu.ay", units: "m/s2"),
        ],
        actuator: [
            SignalDefinition(id: "motor.0", index: 0, name: "motor.0", units: "norm"),
            SignalDefinition(id: "motor.1", index: 1, name: "motor.1", units: "norm"),
        ],
        drive: [
            SignalDefinition(id: "drive.thrust", index: 0, name: "drive.thrust", units: "norm", group: "thrust"),
            SignalDefinition(id: "drive.yaw", index: 1, name: "drive.yaw", units: "norm", group: "yaw"),
        ],
        reflex: [
            SignalDefinition(id: "reflex.0", index: 0, name: "reflex.0", units: "norm"),
        ],
        descending: descendingSignals
    )

    return EmbodimentContract(
        schemaVersion: "kuyu.embodiment.v1",
        contractID: "test-embodiment",
        bodyID: "test-body",
        signals: signals,
        sensors: [
            SensorDefinition(
                id: "imu",
                type: "imu6",
                channels: ["imu.ax", "imu.ay"],
                rateHz: 200,
                latencySeconds: 0.001
            ),
        ],
        actuators: [
            ActuatorDefinition(
                id: "motor.0",
                type: "rotor",
                channels: ["motor.0"],
                limits: ActuatorLimits(min: 0, max: 1, rateLimitPerSecond: 10)
            ),
            ActuatorDefinition(
                id: "motor.1",
                type: "rotor",
                channels: ["motor.1"],
                limits: ActuatorLimits(min: 0, max: 1, rateLimitPerSecond: 10)
            ),
        ],
        control: ControlContract(
            driveChannels: ["drive.thrust", "drive.yaw"],
            reflexChannels: ["reflex.0"],
            descendingChannels: includeDescending ? ["intent.thrust", "intent.yaw"] : nil
        ),
        motorNerve: MotorNerveContract(stages: [
            MotorNerveStageDefinition(
                id: "direct",
                type: .direct,
                inputs: ["drive.thrust", "drive.yaw"],
                outputs: ["motor.0", "motor.1"]
            ),
        ])
    )
}
