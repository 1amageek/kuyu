import Testing
import KuyuScenarios
import KuyuCore
import KuyuPhysics

@Test func longHorizonBenchmarkScaffoldGeneratesCurriculumLevels() throws {
    let suite = try LongHorizonBenchmarkSuite.makeDefault(
        scenariosPerTrack: 2,
        baseSeed: 7
    )

    let tracks = Set(suite.cases.map(\.track))
    #expect(tracks == Set(LongHorizonBenchmarkTrack.allCases))

    let taskCases = suite.cases.filter { $0.track == .longHorizonTask }
    #expect(taskCases.count == 2)
    #expect(taskCases.allSatisfy { $0.definition.config.duration >= 60.0 })

    let disturbanceCases = suite.cases.filter { $0.track == .disturbanceDelayPartialObservability }
    #expect(disturbanceCases.count == 2)
    #expect(disturbanceCases.allSatisfy { !$0.definition.hfEvents.isEmpty })
    #expect(disturbanceCases.allSatisfy { $0.definition.safetyEnvelope.fallVelocityThreshold >= 0.05 })
}

@Test func longHorizonBenchmarkBuildsDeterministicReplayBundle() throws {
    let log = try makeReplayLog()
    let entry = ScenarioLogEntry(
        key: ScenarioKey(scenarioId: log.scenarioId, seed: log.seed),
        log: log
    )

    let bundleA = DeterministicReplayBundle.fromLogs(suiteVersion: "suite-m2", logs: [entry])
    let bundleB = DeterministicReplayBundle.fromLogs(suiteVersion: "suite-m2", logs: [entry])

    #expect(bundleA == bundleB)
    #expect(bundleA.entries.count == 1)
    #expect(bundleA.entries[0].scenarioId == "LH-REPLAY")
}

@Test func longHorizonBenchmarkReportIncludesControlAndTaskCompletionMetrics() throws {
    let evaluations = [
        ScenarioEvaluation(
            scenarioId: try ScenarioID("LH-A"),
            seed: ScenarioSeed(1),
            passed: true,
            maxOmega: 0.5,
            maxTiltDegrees: 10.0,
            sustainedViolationSeconds: 0.0,
            recoveryTimeSeconds: 2.0,
            overshootDegrees: nil,
            hfStabilityScore: 0.9,
            failures: []
        ),
        ScenarioEvaluation(
            scenarioId: try ScenarioID("LH-B"),
            seed: ScenarioSeed(2),
            passed: false,
            maxOmega: 1.2,
            maxTiltDegrees: 30.0,
            sustainedViolationSeconds: 0.2,
            recoveryTimeSeconds: nil,
            overshootDegrees: nil,
            hfStabilityScore: 0.4,
            failures: ["timeout"]
        )
    ]

    let report = LongHorizonBenchmarkReport.fromEvaluations(
        track: .longHorizonTask,
        evaluations: evaluations,
        taskOutcomes: [
            LongHorizonTaskOutcome(
                scenarioId: "LH-A",
                seed: 1,
                completed: true,
                completionTimeSeconds: 6.0
            ),
            LongHorizonTaskOutcome(
                scenarioId: "LH-B",
                seed: 2,
                completed: false,
                completionTimeSeconds: nil
            )
        ]
    )

    #expect(report.control.passRate == 0.5)
    #expect(report.task.completionRate == 0.5)
    #expect(report.task.incompleteRate == 0.5)
    #expect(report.task.averageCompletionTimeSeconds == 6.0)
    #expect(report.entries.count == 2)
}

private func makeReplayLog() throws -> SimulationLog {
    let step = WorldStepLog(
        time: try WorldTime(stepIndex: 0, time: 0.0),
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

    return SimulationLog(
        scenarioId: try ScenarioID("LH-REPLAY"),
        seed: ScenarioSeed(11),
        timeStep: try TimeStep(delta: 0.01),
        determinism: try DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
        configHash: "cfg-lh",
        events: [step],
        failureReason: nil,
        failureTime: nil
    )
}
