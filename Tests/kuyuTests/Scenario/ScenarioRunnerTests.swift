import Testing
@testable import kuyu

@Test(.timeLimit(.minutes(1))) func scenarioRunnerProducesLogs() async throws {
    let timeStep = try TimeStep(delta: 0.001)
    let config = try ScenarioConfig(
        id: ScenarioID("TEST-SCENARIO"),
        seed: ScenarioSeed(1),
        duration: 0.01,
        timeStep: timeStep
    )
    let envelope = try SafetyEnvelope(omegaSafeMax: 20, tiltSafeMaxDegrees: 60, sustainedViolationSeconds: 0.2)
    let definition = ScenarioDefinition(
        config: config,
        kind: .hoverStart,
        initialAttitude: EulerAngles(roll: 0, pitch: 0, yaw: 0),
        initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
        safetyEnvelope: envelope,
        torqueEvents: [],
        actuatorDegradation: nil,
        gyroDriftScale: 1.0
    )

    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: 1)
    let determinism = try DeterminismConfig(tier: .tier0, tier1Tolerance: nil)
    let runner = ScenarioRunner<ImuRateDampingCut, UnusedExternalDAL>(
        schedule: schedule,
        determinism: determinism,
        noise: .zero,
        hoverThrustScale: 1.0
    )

    let hoverThrust = QuadrotorParameters.baseline.mass * QuadrotorParameters.baseline.gravity / 4.0
    let cut = try ImuRateDampingCut(
        hoverThrust: hoverThrust,
        kp: 2.0,
        kd: 0.2,
        yawDamping: 0.1,
        armLength: QuadrotorParameters.baseline.armLength,
        yawCoefficient: QuadrotorParameters.baseline.yawCoefficient
    )

    let log = try runner.runScenario(definition: definition, cut: cut, externalDal: nil)
    #expect(log.events.count == 11)
    #expect(log.events.first?.events.contains(.timeAdvance) == true)
    #expect(log.events.first?.events.contains(.logging) == true)
}
