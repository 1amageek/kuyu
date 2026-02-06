import Testing
import KuyuProfiles
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

@Test(.timeLimit(.minutes(1))) func replayCheckerTier1FlagsScenarioMismatch() async throws {
    let config = try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
    let reference = try makeLog(config: config, scenarioId: "A", positionOffset: 0.0, sensorOffset: 0.0)
    let candidate = try makeLog(config: config, scenarioId: "B", positionOffset: 0.0, sensorOffset: 0.0)
    let result = try ReplayChecker().check(reference: reference, candidate: candidate)
    #expect(!result.passed)
    #expect(result.issues.contains("scenario-id-mismatch"))
}

@Test(.timeLimit(.minutes(1))) func replayCheckerTier1FlagsConfigHashMismatch() async throws {
    let config = try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
    let reference = try makeLog(config: config, configHash: "abc", positionOffset: 0.0, sensorOffset: 0.0)
    let candidate = try makeLog(config: config, configHash: "def", positionOffset: 0.0, sensorOffset: 0.0)
    let result = try ReplayChecker().check(reference: reference, candidate: candidate)
    #expect(!result.passed)
    #expect(result.issues.contains("config-hash-mismatch"))
}

@Test(.timeLimit(.minutes(1))) func replayCheckerRejectsLogShapeMismatch() async throws {
    let config = try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
    let reference = try makeLog(config: config, positionOffset: 0.0, sensorOffset: 0.0, eventCount: 1)
    let candidate = try makeLog(config: config, positionOffset: 0.0, sensorOffset: 0.0, eventCount: 2)

    do {
        _ = try ReplayChecker().check(reference: reference, candidate: candidate)
        #expect(Bool(false))
    } catch let error as ReplayChecker.ReplayError {
        #expect(error == .logShapeMismatch)
    }
}

@Test(.timeLimit(.minutes(1))) func replayCheckerTier1FlagsSensorResidual() async throws {
    let config = try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
    let reference = try makeLog(config: config, positionOffset: 0.0, sensorOffset: 0.0, sensorIndex: 0)
    let candidate = try makeLog(config: config, positionOffset: 0.0, sensorOffset: 0.0, sensorIndex: 1)
    let result = try ReplayChecker().check(reference: reference, candidate: candidate)
    #expect(!result.passed)
    #expect(result.issues.contains("sensor-residual"))
}

private func makeLog(
    config: DeterminismConfig,
    scenarioId: String = "TEST",
    configHash: String = "abc",
    positionOffset: Double,
    sensorOffset: Double,
    sensorIndex: UInt32 = 0,
    eventCount: Int = 1
) throws -> SimulationLog {
    let scenarioId = try ScenarioID(scenarioId)
    let seed = ScenarioSeed(1)
    let timeStep = try TimeStep(delta: 0.001)

    let root = RigidBodySnapshot(
        id: "root",
        position: Axis3(x: positionOffset, y: 0, z: 0),
        velocity: Axis3(x: 0, y: 0, z: 0),
        orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
        angularVelocity: Axis3(x: 0, y: 0, z: 0)
    )
    let stateSnapshot = PlantStateSnapshot(root: root)

    let sample = try ChannelSample(channelIndex: sensorIndex, value: sensorOffset, timestamp: 0.0)
    var events: [WorldStepLog] = []
    for idx in 0..<max(1, eventCount) {
        let step = WorldStepLog(
            time: try WorldTime(stepIndex: UInt64(idx), time: Double(idx) * 0.001),
            events: [.timeAdvance, .logging, .replayCheck],
            sensorSamples: [sample],
            driveIntents: [],
            reflexCorrections: [],
            actuatorValues: [],
            actuatorTelemetry: ActuatorTelemetrySnapshot(
                channels: [ActuatorChannelSnapshot(id: "motor1", value: 1.0, units: "N")]
            ),
            safetyTrace: SafetyTrace(omegaMagnitude: 0, tiltRadians: 0),
            plantState: stateSnapshot,
            disturbances: DisturbanceSnapshot(
                forceWorld: Axis3(x: 0, y: 0, z: 0),
                torqueBody: Axis3(x: 0, y: 0, z: 0)
            )
        )
        events.append(step)
    }

    return SimulationLog(
        scenarioId: scenarioId,
        seed: seed,
        timeStep: timeStep,
        determinism: config,
        configHash: configHash,
        events: events
    )
}
