import Foundation
import Testing
import Logging
import KuyuCore
import KuyuPhysics
import KuyuScenarios

@Test(.timeLimit(.minutes(1))) func runtimeSimulationLoopVerificationPassesForNominalRun() async throws {
    let descriptor = try loadSimulationDescriptorWithLatencyBudgets()
    let adapter = SimulationRuntimeAdapter(
        adapterID: "sim-loop",
        transport: .inProcess,
        descriptor: descriptor
    )
    var events: [RuntimeSessionEvent] = []
    let logger = Logger(label: "kuyu.runtime.looptest")
    let session = try RuntimeSessionCoordinator.startSession(
        adapter: adapter,
        request: RuntimeSessionStartRequest(
            capabilityRequest: RuntimeCapabilityRequest(requireLatencyBudgets: true),
            enforceReflexPathLowLatency: true
        ),
        logger: logger,
        eventSink: { events.append($0) }
    )

    let log = try await runShortScenario(groundZ: 0.0)
    let result = try RuntimeSessionCoordinator.verifySimulationRun(
        session: session,
        log: log,
        logger: logger,
        eventSink: { events.append($0) }
    )

    #expect(result.stepCount == log.events.count)
    #expect(result.cutUpdateCount > 0)
    #expect(result.motorNerveUpdateCount > 0)
    #expect(result.averageStepRateHz > 0)
    #expect(events.map(\.code).contains("session.loop_check_ok"))
}

@Test(.timeLimit(.minutes(1))) func runtimeSimulationLoopVerificationReportsFailureRuns() async throws {
    let descriptor = try loadSimulationDescriptorWithLatencyBudgets()
    let adapter = SimulationRuntimeAdapter(
        adapterID: "sim-loop-failure",
        transport: .inProcess,
        descriptor: descriptor
    )
    var events: [RuntimeSessionEvent] = []
    let logger = Logger(label: "kuyu.runtime.looptest")
    let session = try RuntimeSessionCoordinator.startSession(
        adapter: adapter,
        request: RuntimeSessionStartRequest(
            capabilityRequest: RuntimeCapabilityRequest(requireLatencyBudgets: true),
            enforceReflexPathLowLatency: true
        ),
        logger: logger,
        eventSink: { events.append($0) }
    )

    let log = try await runShortScenario(groundZ: 2.5)
    let result = try RuntimeSessionCoordinator.verifySimulationRun(
        session: session,
        log: log,
        logger: logger,
        eventSink: { events.append($0) }
    )

    #expect(result.failureReason == .groundViolation)
    #expect(events.map(\.code).contains("session.loop_failure_reported"))
    #expect(events.map(\.code).contains("session.loop_check_ok"))
}

private func runShortScenario(groundZ: Double) async throws -> SimulationLog {
    let timeStep = try TimeStep(delta: 0.001)
    let config = try ScenarioConfig(
        id: ScenarioID("RUNTIME-LOOP"),
        seed: ScenarioSeed(3),
        duration: 0.02,
        timeStep: timeStep
    )
    let envelope = try SafetyEnvelope(
        omegaSafeMax: 20,
        tiltSafeMaxDegrees: 60,
        sustainedViolationSeconds: 0.2,
        groundZ: groundZ,
        fallDurationSeconds: 0.5,
        fallVelocityThreshold: 0.0
    )
    let definition = ReferenceQuadrotorScenarioDefinition(
        config: config,
        kind: .hoverStart,
        initialPosition: Axis3(x: 0, y: 0, z: 2.0),
        initialAttitude: EulerAngles(roll: 0, pitch: 0, yaw: 0),
        initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
        safetyEnvelope: envelope,
        torqueEvents: [],
        actuatorDegradation: nil,
        gyroDriftScale: 1.0,
        swapEvents: [],
        hfEvents: []
    )

    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: 1)
    let determinism = try DeterminismConfig(tier: .tier0, tier1Tolerance: nil)
    let runner = ReferenceQuadrotorScenarioRunner<ImuRateDampingDriveCut, FixedQuadMotorNerve>(
        schedule: schedule,
        determinism: determinism,
        noise: .zero,
        hoverThrustScale: 1.0
    )

    let hoverThrust = ReferenceQuadrotorParameters.baseline.mass * ReferenceQuadrotorParameters.baseline.gravity / 4.0
    let cut = try ImuRateDampingDriveCut(
        hoverThrust: hoverThrust,
        kp: 2.0,
        kd: 0.2,
        yawDamping: 0.1,
        armLength: ReferenceQuadrotorParameters.baseline.armLength,
        yawCoefficient: ReferenceQuadrotorParameters.baseline.yawCoefficient,
        maxThrust: ReferenceQuadrotorParameters.baseline.maxThrust
    )
    let maxThrusts = try MotorMaxThrusts.uniform(ReferenceQuadrotorParameters.baseline.maxThrust)
    let motorNerve = FixedQuadMotorNerve(config: FixedQuadMotorNerve.Config(
        mixer: ReferenceQuadrotorMixer(
            armLength: ReferenceQuadrotorParameters.baseline.armLength,
            yawCoefficient: ReferenceQuadrotorParameters.baseline.yawCoefficient
        ),
        motorMaxThrusts: maxThrusts
    ))

    return try await runner.runScenario(
        definition: definition,
        cut: cut,
        motorNerve: motorNerve
    )
}

private func loadSimulationDescriptorWithLatencyBudgets() throws -> RobotDescriptor {
    let loaded = try loadBundledDescriptor(relativePath: "Sources/KuyuUI/Resources/Models/QuadRef/quadref.model.json").descriptor
    return RobotDescriptor(
        robot: loaded.robot,
        physics: loaded.physics,
        render: loaded.render,
        signals: loaded.signals,
        sensors: loaded.sensors,
        actuators: loaded.actuators,
        control: RobotDescriptor.Control(
            driveChannels: loaded.control.driveChannels,
            reflexChannels: loaded.control.reflexChannels,
            descendingChannels: loaded.control.descendingChannels,
            summaryChannels: loaded.control.summaryChannels,
            constraints: loaded.control.constraints,
            latencyBudgetsMs: RobotDescriptor.LatencyBudgetsMs(
                reflexPathBudgetMs: 2.0,
                corePathBudgetMs: 8.0,
                descendingApplyBudgetMs: 8.0,
                summaryExportBudgetMs: 20.0
            )
        ),
        observation: loaded.observation,
        motorNerve: loaded.motorNerve
    )
}

private func loadBundledDescriptor(relativePath: String) throws -> LoadedRobotDescriptor {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let packageRoot = testFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let descriptorPath = packageRoot.appendingPathComponent(relativePath).path
    return try RobotDescriptorLoader().loadDescriptor(path: descriptorPath)
}
