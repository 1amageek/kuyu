import Testing
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

@Test func parametricScenarioGeneratorIsDeterministicForSeededCurriculum() throws {
    let generator = ParametricScenarioGenerator()
    let first = try generator.generateCurriculum(
        levels: 2,
        scenariosPerLevel: 3,
        baseSeed: 42
    )
    let second = try generator.generateCurriculum(
        levels: 2,
        scenariosPerLevel: 3,
        baseSeed: 42
    )

    #expect(first == second)
}

@Test func parallelDataCollectorAggregatesRecordsAndEvaluations() throws {
    let definitionA = try makeDefinition(id: "COLLECT-A", seed: 10)
    let definitionB = try makeDefinition(id: "COLLECT-B", seed: 11)
    let logA = try makeLog(id: "COLLECT-A", seed: 10, steps: 2)
    let logB = try makeLog(id: "COLLECT-B", seed: 11, steps: 3)

    let buffer = try OnlineDataBuffer(maxRecords: 32)
    let collector = ParallelDataCollector(buffer: buffer)
    let result = try collector.collect(
        logs: [logA, logB],
        definitions: [definitionA, definitionB]
    )

    #expect(result.recordsCollected == 5)
    #expect(result.evaluations.count == 2)
    #expect(buffer.count == 5)
}

@Test func curriculumControllerProgressionIsPolicyControlledAndReproducible() throws {
    let config = try CurriculumController.Config(
        totalLevels: 3,
        scenariosPerLevel: 2,
        advanceThreshold: 0.5,
        maxEpochsPerLevel: 2
    )

    var left = CurriculumController(config: config)
    var right = CurriculumController(config: config)

    let passThenFail = [
        try makeExtendedEvaluation(id: "CURR-1", seed: 1, passed: true),
        try makeExtendedEvaluation(id: "CURR-2", seed: 2, passed: false),
    ]
    let failOnly = [
        try makeExtendedEvaluation(id: "CURR-3", seed: 3, passed: false),
        try makeExtendedEvaluation(id: "CURR-4", seed: 4, passed: false),
    ]

    let a1 = left.report(evaluations: passThenFail)
    let b1 = right.report(evaluations: passThenFail)
    #expect(a1 == b1)
    #expect(left.currentLevel == 1)

    let a2 = left.report(evaluations: failOnly)
    let b2 = right.report(evaluations: failOnly)
    #expect(a2 == b2)
    #expect(left.currentLevel == 1)
    #expect(left.epochsAtCurrentLevel == 1)

    let a3 = left.report(evaluations: failOnly)
    let b3 = right.report(evaluations: failOnly)
    #expect(a3 == b3)
    #expect(left.currentLevel == 2)

    #expect(left.levelHistory == right.levelHistory)
}

private func makeDefinition(id: String, seed: UInt64) throws -> ReferenceQuadrotorScenarioDefinition {
    let timeStep = try TimeStep(delta: 0.01)
    let config = try ScenarioConfig(
        id: ScenarioID(id),
        seed: ScenarioSeed(seed),
        duration: 0.05,
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
    return ReferenceQuadrotorScenarioDefinition(
        config: config,
        kind: .hoverStart,
        initialPosition: Axis3(x: 0, y: 0, z: 2),
        initialAttitude: EulerAngles(roll: 0, pitch: 0, yaw: 0),
        initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
        safetyEnvelope: envelope,
        torqueEvents: [],
        actuatorDegradation: nil,
        gyroDriftScale: 1.0,
        swapEvents: [],
        hfEvents: []
    )
}

private func makeLog(id: String, seed: UInt64, steps: Int) throws -> SimulationLog {
    let stepLogs = try (0..<steps).map { index in
        try WorldStepLog(
            time: WorldTime(stepIndex: UInt64(index), time: Double(index) * 0.01),
            events: [.timeAdvance, .logging],
            sensorSamples: [],
            driveIntents: [],
            reflexCorrections: [],
            actuatorValues: [],
            actuatorTelemetry: ActuatorTelemetrySnapshot(channels: []),
            safetyTrace: try SafetyTrace(omegaMagnitude: 0.0, tiltRadians: 0.0),
            plantState: PlantStateSnapshot(
                root: RigidBodySnapshot(
                    id: "root",
                    position: Axis3(x: 0, y: 0, z: 2),
                    velocity: Axis3(x: 0, y: 0, z: 0),
                    orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
                    angularVelocity: Axis3(x: 0, y: 0, z: 0)
                )
            ),
            disturbances: DisturbanceSnapshot(
                forceWorld: Axis3(x: 0, y: 0, z: 0),
                torqueBody: Axis3(x: 0, y: 0, z: 0)
            )
        )
    }

    return try SimulationLog(
        scenarioId: ScenarioID(id),
        seed: ScenarioSeed(seed),
        timeStep: TimeStep(delta: 0.01),
        determinism: DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
        configHash: "cfg-\(id)",
        events: stepLogs
    )
}

private func makeExtendedEvaluation(id: String, seed: UInt64, passed: Bool) throws -> ExtendedScenarioEvaluation {
    let base = ScenarioEvaluation(
        scenarioId: try ScenarioID(id),
        seed: ScenarioSeed(seed),
        passed: passed,
        maxOmega: 0.0,
        maxTiltDegrees: 0.0,
        sustainedViolationSeconds: 0.0,
        recoveryTimeSeconds: nil,
        overshootDegrees: nil,
        hfStabilityScore: nil,
        failures: []
    )
    return ExtendedScenarioEvaluation(base: base, controlQuality: nil, inverseDynamics: nil)
}
