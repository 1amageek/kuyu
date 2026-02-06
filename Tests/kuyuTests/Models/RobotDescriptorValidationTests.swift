import Testing
import KuyuProfiles

@Test func robotDescriptorValidationAcceptsDescriptorWithoutFrameBindings() async throws {
    let descriptor = makeDescriptor(engineID: "kuyu.physics")
    try descriptor.validate()
}

@Test func robotDescriptorValidationRejectsEmptyEngineID() async throws {
    let descriptor = makeDescriptor(engineID: " ")
    do {
        try descriptor.validate()
        #expect(Bool(false))
    } catch let error as RobotDescriptor.ValidationError {
        #expect(error == .empty("physics.engine.id"))
    }
}

@Test func robotDescriptorValidationRejectsUnsupportedPhysicsFormat() async throws {
    let descriptor = RobotDescriptor(
        robot: RobotDescriptor.Robot(robotID: "robot", name: "Robot", category: "aerial"),
        physics: RobotDescriptor.Physics(
            model: RobotDescriptor.PhysicsModel(format: .sdf, path: "robot.sdf"),
            engine: RobotDescriptor.EngineBinding(id: "kuyu.physics")
        ),
        signals: RobotDescriptor.Signals(
            sensor: [],
            actuator: [],
            drive: [RobotDescriptor.SignalDefinition(id: "drive0", index: 0, name: "drive0", units: "norm")],
            reflex: [RobotDescriptor.SignalDefinition(id: "reflex0", index: 0, name: "reflex0", units: "norm")]
        ),
        sensors: [],
        actuators: [],
        control: RobotDescriptor.Control(driveChannels: ["drive0"], reflexChannels: ["reflex0"]),
        motorNerve: RobotDescriptor.MotorNerveDescriptor(
            stages: [
                RobotDescriptor.MotorNerveStage(
                    id: "passthrough",
                    type: .direct,
                    inputs: ["drive0"],
                    outputs: []
                )
            ]
        )
    )

    do {
        try descriptor.validate()
        #expect(Bool(false))
    } catch let error as RobotDescriptor.ValidationError {
        #expect(error == .invalidPhysicsFormat("physics.model.format"))
    }
}

private func makeDescriptor(engineID: String) -> RobotDescriptor {
    let signals = RobotDescriptor.Signals(
        sensor: [
            RobotDescriptor.SignalDefinition(
                id: "imu_accel_z",
                index: 0,
                name: "IMU Accel Z",
                units: "m/s^2",
                rateHz: 200
            )
        ],
        actuator: [
            RobotDescriptor.SignalDefinition(
                id: "motor_1",
                index: 0,
                name: "Motor 1",
                units: "N"
            )
        ],
        drive: [
            RobotDescriptor.SignalDefinition(
                id: "drive_lift",
                index: 0,
                name: "Drive Lift",
                units: "norm",
                range: RobotDescriptor.Range(min: 0, max: 1)
            )
        ],
        reflex: [
            RobotDescriptor.SignalDefinition(
                id: "reflex_lift",
                index: 0,
                name: "Reflex Lift",
                units: "norm",
                range: RobotDescriptor.Range(min: -1, max: 1)
            )
        ]
    )

    return RobotDescriptor(
        robot: RobotDescriptor.Robot(robotID: "singleprop-ref", name: "Single Prop", category: "aerial"),
        physics: RobotDescriptor.Physics(
            model: RobotDescriptor.PhysicsModel(format: .urdf, path: "singleprop.urdf"),
            engine: RobotDescriptor.EngineBinding(id: engineID)
        ),
        signals: signals,
        sensors: [
            RobotDescriptor.SensorDefinition(
                id: "imu",
                type: "imu6",
                channels: ["imu_accel_z"],
                rateHz: 200,
                latencyMs: 2
            )
        ],
        actuators: [
            RobotDescriptor.ActuatorDefinition(
                id: "motor",
                type: "motor",
                channels: ["motor_1"],
                limits: RobotDescriptor.ActuatorLimits(min: 0, max: 12, rateLimit: 200)
            )
        ],
        control: RobotDescriptor.Control(
            driveChannels: ["drive_lift"],
            reflexChannels: ["reflex_lift"],
            constraints: RobotDescriptor.ControlConstraints(
                driveClamp: RobotDescriptor.Range(min: 0, max: 1),
                reflexClamp: RobotDescriptor.Range(min: -1, max: 1)
            )
        ),
        motorNerve: RobotDescriptor.MotorNerveDescriptor(
            stages: [
                RobotDescriptor.MotorNerveStage(
                    id: "direct",
                    type: .direct,
                    inputs: ["drive_lift"],
                    outputs: ["motor_1"]
                )
            ]
        )
    )
}
