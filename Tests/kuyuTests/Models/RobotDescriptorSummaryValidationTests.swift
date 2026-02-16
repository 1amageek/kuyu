import Testing
import KuyuPhysics

@Test func robotDescriptorValidationAcceptsSummaryChannelsWhenDefined() async throws {
    let base = makeSummaryDescriptorBase()
    let descriptor = RobotDescriptor(
        robot: base.robot,
        physics: base.physics,
        render: base.render,
        signals: RobotDescriptor.Signals(
            sensor: base.signals.sensor,
            actuator: base.signals.actuator,
            drive: base.signals.drive,
            reflex: base.signals.reflex,
            descending: base.signals.descending,
            summary: [
                RobotDescriptor.SignalDefinition(id: "summary.risk", index: 0, name: "summary.risk", units: "norm")
            ],
            motorNerve: base.signals.motorNerve
        ),
        sensors: base.sensors,
        actuators: base.actuators,
        control: RobotDescriptor.Control(
            driveChannels: base.control.driveChannels,
            reflexChannels: base.control.reflexChannels,
            summaryChannels: ["summary.risk"],
            constraints: base.control.constraints
        ),
        motorNerve: base.motorNerve
    )

    try descriptor.validate()
}

@Test func robotDescriptorValidationRejectsUnknownSummaryChannelRef() async throws {
    let base = makeSummaryDescriptorBase()
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
            summaryChannels: ["summary.missing"],
            constraints: base.control.constraints
        ),
        motorNerve: base.motorNerve
    )

    do {
        try descriptor.validate()
        #expect(Bool(false))
    } catch let error as RobotDescriptor.ValidationError {
        #expect(error == .unknownSignalRef("summary.missing"))
    }
}

private func makeSummaryDescriptorBase() -> RobotDescriptor {
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
        robot: RobotDescriptor.Robot(robotID: "summary-ref", name: "Summary Ref", category: "aerial"),
        physics: RobotDescriptor.Physics(
            model: RobotDescriptor.PhysicsModel(format: .urdf, path: "summary.urdf"),
            engine: RobotDescriptor.EngineBinding(id: "kuyu.physics")
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
