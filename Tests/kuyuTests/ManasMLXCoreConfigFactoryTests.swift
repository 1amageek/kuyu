import Testing
@testable import KuyuMLX
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

@MainActor
@Test func coreConfigWithoutDescriptorUsesLegacyMode() {
    let config = ManasMLXModelStore.makeCoreConfig(
        inputSize: 12,
        driveCount: 4,
        auxEnabled: true,
        descriptor: nil
    )

    #expect(config.useSharedEncoder == false)
    #expect(config.useSharedDecoder == false)
    #expect(config.typeEmbeddingDim == 0)
    #expect(config.typeEmbeddingCount == 0)
    #expect(config.ascendingTypeIndices == nil)
    #expect(config.actuatorTypeIndices == nil)
}

@MainActor
@Test func coreConfigWithDescriptorUsesSharedTypedMode() {
    let descriptor = makeDescriptor(includeDescending: false)
    let config = ManasMLXModelStore.makeCoreConfig(
        inputSize: 8,
        driveCount: 2,
        auxEnabled: false,
        descriptor: descriptor
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
    let descriptor = makeDescriptor(includeDescending: true)
    let config = ManasMLXModelStore.makeCoreConfig(
        inputSize: 8,
        driveCount: 2,
        auxEnabled: false,
        descriptor: descriptor
    )

    #expect(config.descendingSize == 2)
    #expect(config.descendingEmbeddingSize == 16)
    #expect(config.descendingTypeIndices == [4, 5])
    #expect(config.actuatorTypeIndices == [6, 7])
    #expect(config.typeEmbeddingCount == 8)
}

private func makeDescriptor(includeDescending: Bool) -> RobotDescriptor {
    let descendingSignals: [RobotDescriptor.SignalDefinition]? = includeDescending ? [
        RobotDescriptor.SignalDefinition(
            id: "intent.thrust",
            index: 0,
            name: "intent.thrust",
            units: "norm",
            group: "intent.thrust"
        ),
        RobotDescriptor.SignalDefinition(
            id: "intent.yaw",
            index: 1,
            name: "intent.yaw",
            units: "norm",
            group: "intent.yaw"
        ),
    ] : nil

    let signals = RobotDescriptor.Signals(
        sensor: [
            RobotDescriptor.SignalDefinition(id: "imu.ax", index: 0, name: "imu.ax", units: "m/s2"),
            RobotDescriptor.SignalDefinition(id: "imu.ay", index: 1, name: "imu.ay", units: "m/s2"),
        ],
        actuator: [
            RobotDescriptor.SignalDefinition(id: "motor.0", index: 0, name: "motor.0", units: "norm"),
            RobotDescriptor.SignalDefinition(id: "motor.1", index: 1, name: "motor.1", units: "norm"),
        ],
        drive: [
            RobotDescriptor.SignalDefinition(id: "drive.thrust", index: 0, name: "drive.thrust", units: "norm", group: "thrust"),
            RobotDescriptor.SignalDefinition(id: "drive.yaw", index: 1, name: "drive.yaw", units: "norm", group: "yaw"),
        ],
        reflex: [
            RobotDescriptor.SignalDefinition(id: "reflex.0", index: 0, name: "reflex.0", units: "norm"),
        ],
        descending: descendingSignals
    )

    return RobotDescriptor(
        robot: RobotDescriptor.Robot(robotID: "test", name: "Test", category: "aerial"),
        physics: RobotDescriptor.Physics(
            model: RobotDescriptor.PhysicsModel(format: .urdf, path: "test.urdf"),
            engine: RobotDescriptor.EngineBinding(id: "kuyu.physics")
        ),
        signals: signals,
        sensors: [
            RobotDescriptor.SensorDefinition(
                id: "imu",
                type: "imu6",
                channels: ["imu.ax", "imu.ay"],
                rateHz: 200,
                latencyMs: 1.0
            ),
        ],
        actuators: [
            RobotDescriptor.ActuatorDefinition(
                id: "motor.0",
                type: "rotor",
                channels: ["motor.0"],
                limits: RobotDescriptor.ActuatorLimits(min: 0, max: 1, rateLimit: 10)
            ),
            RobotDescriptor.ActuatorDefinition(
                id: "motor.1",
                type: "rotor",
                channels: ["motor.1"],
                limits: RobotDescriptor.ActuatorLimits(min: 0, max: 1, rateLimit: 10)
            ),
        ],
        control: RobotDescriptor.Control(
            driveChannels: ["drive.thrust", "drive.yaw"],
            reflexChannels: ["reflex.0"],
            descendingChannels: includeDescending ? ["intent.thrust", "intent.yaw"] : nil
        ),
        motorNerve: RobotDescriptor.MotorNerveDescriptor(stages: [
            RobotDescriptor.MotorNerveStage(
                id: "direct",
                type: .direct,
                inputs: ["drive.thrust", "drive.yaw"],
                outputs: ["motor.0", "motor.1"]
            ),
        ])
    )
}
