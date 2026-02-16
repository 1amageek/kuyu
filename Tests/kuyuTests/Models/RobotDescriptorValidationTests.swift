import Testing
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

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

@Test func robotDescriptorValidationAcceptsDescendingChannelsWhenDefined() async throws {
    var descriptor = makeDescriptor(engineID: "kuyu.physics")
    descriptor = RobotDescriptor(
        robot: descriptor.robot,
        physics: descriptor.physics,
        render: descriptor.render,
        signals: RobotDescriptor.Signals(
            sensor: descriptor.signals.sensor,
            actuator: descriptor.signals.actuator,
            drive: descriptor.signals.drive,
            reflex: descriptor.signals.reflex,
            descending: [
                RobotDescriptor.SignalDefinition(id: "intent.thrust", index: 0, name: "intent.thrust", units: "norm")
            ],
            motorNerve: descriptor.signals.motorNerve
        ),
        sensors: descriptor.sensors,
        actuators: descriptor.actuators,
        control: RobotDescriptor.Control(
            driveChannels: descriptor.control.driveChannels,
            reflexChannels: descriptor.control.reflexChannels,
            descendingChannels: ["intent.thrust"],
            constraints: descriptor.control.constraints
        ),
        motorNerve: descriptor.motorNerve
    )

    try descriptor.validate()
}

@Test func robotDescriptorValidationRejectsUnknownDescendingChannelRef() async throws {
    let base = makeDescriptor(engineID: "kuyu.physics")
    let descriptor = RobotDescriptor(
        robot: base.robot,
        physics: base.physics,
        render: base.render,
        signals: base.signals,
        sensors: base.sensors,
        actuators: base.actuators,
        control: RobotDescriptor.Control(
            driveChannels: base.control.driveChannels,
            reflexChannels: base.control.reflexChannels,
            descendingChannels: ["intent.missing"],
            constraints: base.control.constraints
        ),
        motorNerve: base.motorNerve
    )

    do {
        try descriptor.validate()
        #expect(Bool(false))
    } catch let error as RobotDescriptor.ValidationError {
        #expect(error == .unknownSignalRef("intent.missing"))
    }
}

@Test func robotDescriptorValidationAcceptsObservationMetadata() async throws {
    let base = makeDescriptor(engineID: "kuyu.physics")
    let descriptor = RobotDescriptor(
        robot: base.robot,
        physics: base.physics,
        render: base.render,
        signals: base.signals,
        sensors: base.sensors,
        actuators: base.actuators,
        control: base.control,
        observation: RobotDescriptor.Observation(
            clock: RobotDescriptor.ObservationClock(
                timebase: "monotonic",
                epoch: "boot",
                maxSkewMs: 4.0,
                syncPolicy: .soft
            ),
            modalities: [
                RobotDescriptor.ModalityDefinition(
                    id: "imu",
                    type: .state,
                    channels: ["imu_accel_z"],
                    timestampSource: "imuClock",
                    provenance: RobotDescriptor.ObservationProvenance(
                        producer: "imu-sensorhub",
                        transport: "shared-memory",
                        notes: "primary path"
                    )
                )
            ]
        ),
        motorNerve: base.motorNerve
    )

    try descriptor.validate()
}

@Test func robotDescriptorValidationRejectsObservationUnknownChannelRef() async throws {
    let base = makeDescriptor(engineID: "kuyu.physics")
    let descriptor = RobotDescriptor(
        robot: base.robot,
        physics: base.physics,
        render: base.render,
        signals: base.signals,
        sensors: base.sensors,
        actuators: base.actuators,
        control: base.control,
        observation: RobotDescriptor.Observation(
            clock: RobotDescriptor.ObservationClock(
                timebase: "monotonic",
                maxSkewMs: 2.0,
                syncPolicy: .hard
            ),
            modalities: [
                RobotDescriptor.ModalityDefinition(
                    id: "cameraFront",
                    type: .vision,
                    channels: ["missing.signal"],
                    timestampSource: "camClock"
                )
            ]
        ),
        motorNerve: base.motorNerve
    )

    do {
        try descriptor.validate()
        #expect(Bool(false))
    } catch let error as RobotDescriptor.ValidationError {
        #expect(error == .unknownSignalRef("missing.signal"))
    }
}

@Test func robotDescriptorValidationRejectsObservationNegativeSkew() async throws {
    let base = makeDescriptor(engineID: "kuyu.physics")
    let descriptor = RobotDescriptor(
        robot: base.robot,
        physics: base.physics,
        render: base.render,
        signals: base.signals,
        sensors: base.sensors,
        actuators: base.actuators,
        control: base.control,
        observation: RobotDescriptor.Observation(
            clock: RobotDescriptor.ObservationClock(
                timebase: "monotonic",
                maxSkewMs: -0.1,
                syncPolicy: .hard
            )
        ),
        motorNerve: base.motorNerve
    )

    do {
        try descriptor.validate()
        #expect(Bool(false))
    } catch let error as RobotDescriptor.ValidationError {
        #expect(error == .invalidRange("observation.clock.maxSkewMs"))
    }
}

@Test func robotDescriptorValidationRejectsDescendingAsMotorNerveInput() async throws {
    let base = makeDescriptor(engineID: "kuyu.physics")
    let descriptor = RobotDescriptor(
        robot: base.robot,
        physics: base.physics,
        render: base.render,
        signals: RobotDescriptor.Signals(
            sensor: base.signals.sensor,
            actuator: base.signals.actuator,
            drive: base.signals.drive,
            reflex: base.signals.reflex,
            descending: [
                RobotDescriptor.SignalDefinition(id: "intent.thrust", index: 0, name: "intent.thrust", units: "norm")
            ],
            motorNerve: base.signals.motorNerve
        ),
        sensors: base.sensors,
        actuators: base.actuators,
        control: RobotDescriptor.Control(
            driveChannels: base.control.driveChannels,
            reflexChannels: base.control.reflexChannels,
            descendingChannels: ["intent.thrust"],
            constraints: base.control.constraints
        ),
        motorNerve: RobotDescriptor.MotorNerveDescriptor(
            stages: [
                RobotDescriptor.MotorNerveStage(
                    id: "invalid",
                    type: .direct,
                    inputs: ["intent.thrust"],
                    outputs: ["motor_1"]
                )
            ]
        )
    )

    do {
        try descriptor.validate()
        #expect(Bool(false))
    } catch let error as RobotDescriptor.ValidationError {
        #expect(error == .unknownSignalRef("intent.thrust"))
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
