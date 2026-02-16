import Testing
import KuyuCore
import KuyuPhysics

@Test func robotDescriptorValidationAcceptsLatencyBudgetDeclaration() async throws {
    let descriptor = makeLatencyDescriptor(
        budgets: RobotDescriptor.LatencyBudgetsMs(
            reflexPathBudgetMs: 2.0,
            corePathBudgetMs: 8.0,
            descendingApplyBudgetMs: 8.0,
            summaryExportBudgetMs: 20.0
        )
    )

    try descriptor.validate()
}

@Test func robotDescriptorValidationRejectsNonPositiveLatencyBudget() async throws {
    let descriptor = makeLatencyDescriptor(
        budgets: RobotDescriptor.LatencyBudgetsMs(
            reflexPathBudgetMs: 0.0,
            corePathBudgetMs: 8.0,
            descendingApplyBudgetMs: 8.0,
            summaryExportBudgetMs: 20.0
        )
    )

    do {
        try descriptor.validate()
        #expect(Bool(false))
    } catch let error as RobotDescriptor.ValidationError {
        #expect(error == .invalidRange("control.latencyBudgetsMs.reflexPathBudgetMs"))
    }
}

@Test func latencyBudgetViolationRequiresContractFields() throws {
    let violation = try LatencyBudgetViolation(
        path: "reflexPath",
        budgetMs: 2.0,
        observedMs: 2.7,
        time: 1.2,
        reason: "scheduler-jitter"
    )

    #expect(violation.path == "reflexPath")
    #expect(violation.budgetMs == 2.0)
    #expect(violation.observedMs == 2.7)
    #expect(violation.time == 1.2)
    #expect(violation.reason == "scheduler-jitter")
}

@Test func latencyBudgetViolationRejectsEmptyPath() throws {
    do {
        _ = try LatencyBudgetViolation(
            path: " ",
            budgetMs: 2.0,
            observedMs: 2.7,
            time: 1.2,
            reason: "scheduler-jitter"
        )
        #expect(Bool(false))
    } catch let error as LatencyBudgetViolation.ValidationError {
        #expect(error == .empty("path"))
    }
}

private func makeLatencyDescriptor(budgets: RobotDescriptor.LatencyBudgetsMs) -> RobotDescriptor {
    let signals = RobotDescriptor.Signals(
        sensor: [
            RobotDescriptor.SignalDefinition(id: "imu_accel_z", index: 0, name: "IMU Accel Z", units: "m/s^2")
        ],
        actuator: [
            RobotDescriptor.SignalDefinition(id: "motor_1", index: 0, name: "Motor 1", units: "N")
        ],
        drive: [
            RobotDescriptor.SignalDefinition(id: "drive_lift", index: 0, name: "Drive Lift", units: "norm")
        ],
        reflex: [
            RobotDescriptor.SignalDefinition(id: "reflex_lift", index: 0, name: "Reflex Lift", units: "norm")
        ]
    )

    return RobotDescriptor(
        robot: RobotDescriptor.Robot(robotID: "latency-ref", name: "Latency Ref", category: "aerial"),
        physics: RobotDescriptor.Physics(
            model: RobotDescriptor.PhysicsModel(format: .urdf, path: "latency.urdf"),
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
            ),
            latencyBudgetsMs: budgets
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
