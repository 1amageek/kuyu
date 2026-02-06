import Testing
import KuyuProfiles
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func scenarioRunnerProducesLogs() async throws {
    let timeStep = try TimeStep(delta: 0.001)
    let config = try ScenarioConfig(
        id: ScenarioID("TEST-SCENARIO"),
        seed: ScenarioSeed(1),
        duration: 0.01,
        timeStep: timeStep
    )
    let envelope = try SafetyEnvelope(
        omegaSafeMax: 20,
        tiltSafeMaxDegrees: 60,
        sustainedViolationSeconds: 0.2,
        groundZ: 0.0,
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
    let motorNerveConfig = FixedQuadMotorNerve.Config(
        mixer: ReferenceQuadrotorMixer(
            armLength: ReferenceQuadrotorParameters.baseline.armLength,
            yawCoefficient: ReferenceQuadrotorParameters.baseline.yawCoefficient
        ),
        motorMaxThrusts: maxThrusts
    )
    let log = try await runner.runScenario(
        definition: definition,
        cut: cut,
        motorNerve: FixedQuadMotorNerve(config: motorNerveConfig)
    )
    #expect(log.events.count == 10)
    #expect(log.events.first?.events.contains(ExecutionEvent.timeAdvance) == true)
    #expect(log.events.first?.events.contains(ExecutionEvent.logging) == true)
    #expect(log.events.first?.events.contains(ExecutionEvent.motorNerveUpdate) == true)
}
