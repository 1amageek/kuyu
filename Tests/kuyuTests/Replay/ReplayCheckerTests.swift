import Testing
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func replayCheckerTier0ExactMatch() async throws {
    let log = try makeLog(config: DeterminismConfig(tier: .tier0, tier1Tolerance: nil), positionOffset: 0.0, sensorOffset: 0.0)
    let result = try ReplayChecker().check(reference: log, candidate: log)
    #expect(result.passed)
    #expect(result.tier == .tier0)
}

@Test(.timeLimit(.minutes(1))) func replayCheckerTier1WithinTolerance() async throws {
    let config = try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
    let reference = try makeLog(config: config, positionOffset: 0.0, sensorOffset: 0.0)
    let candidate = try makeLog(config: config, positionOffset: 5e-5, sensorOffset: 5e-5)
    let result = try ReplayChecker().check(reference: reference, candidate: candidate)
    #expect(result.passed)
    #expect(result.tier == .tier1)
}

@Test(.timeLimit(.minutes(1))) func replayCheckerTier1DetectsExcessResidual() async throws {
    let config = try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
    let reference = try makeLog(config: config, positionOffset: 0.0, sensorOffset: 0.0)
    let candidate = try makeLog(config: config, positionOffset: 1e-2, sensorOffset: 0.0)
    let result = try ReplayChecker().check(reference: reference, candidate: candidate)
    #expect(!result.passed)
    #expect(result.issues.contains("position-residual"))
}

@Test(.timeLimit(.minutes(1))) func replayCheckerRejectsTierMismatch() async throws {
    let reference = try makeLog(config: DeterminismConfig(tier: .tier0, tier1Tolerance: nil), positionOffset: 0, sensorOffset: 0)
    let candidate = try makeLog(config: DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline), positionOffset: 0, sensorOffset: 0)

    do {
        _ = try ReplayChecker().check(reference: reference, candidate: candidate)
        #expect(Bool(false))
    } catch let error as ReplayChecker.ReplayError {
        #expect(error == .tierMismatch)
    }
}

private func makeLog(config: DeterminismConfig, positionOffset: Double, sensorOffset: Double) throws -> SimulationLog {
    let scenarioId = try ScenarioID("TEST")
    let seed = ScenarioSeed(1)
    let timeStep = try TimeStep(delta: 0.001)

    let stateSnapshot = QuadrotorStateSnapshot(
        position: Axis3(x: positionOffset, y: 0, z: 0),
        velocity: Axis3(x: 0, y: 0, z: 0),
        orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
        angularVelocity: Axis3(x: 0, y: 0, z: 0)
    )

    let sample = try ChannelSample(channelIndex: 0, value: sensorOffset, timestamp: 0.0)
    let step = WorldStepLog(
        time: try WorldTime(stepIndex: 0, time: 0.0),
        events: [.timeAdvance, .logging, .replayCheck],
        sensorSamples: [sample],
        driveIntents: [],
        reflexCorrections: [],
        actuatorCommands: [],
        motorThrusts: try MotorThrusts.uniform(1.0),
        safetyTrace: SafetyTrace(omegaMagnitude: 0, tiltRadians: 0),
        stateSnapshot: stateSnapshot,
        disturbanceTorqueBody: Axis3(x: 0, y: 0, z: 0),
        disturbanceForceWorld: Axis3(x: 0, y: 0, z: 0)
    )

    return SimulationLog(
        scenarioId: scenarioId,
        seed: seed,
        timeStep: timeStep,
        determinism: config,
        configHash: "abc",
        events: [step]
    )
}
