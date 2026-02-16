import Testing
import KuyuCore
import KuyuPhysics
import KuyuScenarios

@Test(.timeLimit(.minutes(1))) func scenarioRunnerPopulatesObservabilityBundleFromExecutionPath() async throws {
    let timeStep = try TimeStep(delta: 0.001)
    let config = try ScenarioConfig(
        id: ScenarioID("OBS-INTEGRATION"),
        seed: ScenarioSeed(5),
        duration: 0.02,
        timeStep: timeStep
    )
    let envelope = try SafetyEnvelope(
        omegaSafeMax: 20,
        tiltSafeMaxDegrees: 60,
        sustainedViolationSeconds: 0.2,
        groundZ: 2.5,
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
    let runner = ReferenceQuadrotorScenarioRunner<ObservabilityCut, FixedQuadMotorNerve>(
        schedule: schedule,
        determinism: determinism,
        noise: .zero,
        hoverThrustScale: 1.0
    )
    let maxThrusts = try MotorMaxThrusts.uniform(ReferenceQuadrotorParameters.baseline.maxThrust)
    let motorNerve = FixedQuadMotorNerve(config: FixedQuadMotorNerve.Config(
        mixer: ReferenceQuadrotorMixer(
            armLength: ReferenceQuadrotorParameters.baseline.armLength,
            yawCoefficient: ReferenceQuadrotorParameters.baseline.yawCoefficient
        ),
        motorMaxThrusts: maxThrusts
    ))

    let log = try await runner.runScenario(
        definition: definition,
        cut: ObservabilityCut(),
        motorNerve: motorNerve
    )

    #expect(log.failureReason == .groundViolation)
    #expect(log.observability != nil)
    #expect(log.observability?.plannerDecisions.isEmpty == false)
    #expect(log.observability?.adapterMappings.isEmpty == false)
    #expect(log.observability?.memoryRecalls.isEmpty == false)
    #expect(log.observability?.fallbackTransitions.isEmpty == false)
    #expect(log.observability?.latencyBudgetViolations.isEmpty == false)
    #expect(log.observability?.incidents.isEmpty == false)
    #expect(log.observability?.upwardSummaries.count == log.events.count)
    #expect(log.observability?.arbitrationOutcomes.isEmpty == false)
}

private struct ObservabilityCut: CutInterface, CutObservabilityProviding {
    private var pending = CutObservabilityEvents()

    mutating func update(samples: [ChannelSample], time: WorldTime) throws -> CutOutput {
        _ = samples
        pending = CutObservabilityEvents(
            plannerDecisions: [
                PlannerDecisionLog(
                    time: time.time,
                    plannerID: "planner.mock",
                    decision: "keep-hover",
                    descendingSnapshot: [0.2, 0.2, 0.2, 0.2]
                )
            ],
            adapterMappings: [
                AdapterMappingLog(
                    time: time.time,
                    adapterID: "adapter.mock",
                    fromDomain: "multimodal",
                    toDomain: "ascending",
                    mappedChannels: ["imu.ax", "imu.az"]
                )
            ],
            memoryRecalls: [
                MemoryRecallLog(
                    time: time.time,
                    task: "hover",
                    morphology: "quad",
                    scenarioID: "OBS-INTEGRATION",
                    seed: 5,
                    appliedDescendingChannels: ["desc.roll", "desc.pitch"]
                )
            ],
            fallbackTransitions: [
                FallbackTransitionLog(
                    time: time.time,
                    from: "planner.mock",
                    to: "hold-last",
                    reason: "planner-timeout"
                )
            ],
            latencyBudgetViolations: [
                try LatencyBudgetViolation(
                    path: "reflexPath",
                    budgetMs: 2.0,
                    observedMs: 2.5,
                    time: time.time,
                    reason: "scheduler-jitter"
                )
            ]
        )

        let drives = try [
            DriveIntent(index: DriveIndex(0), activation: 0.2),
            DriveIntent(index: DriveIndex(1), activation: 0.2),
            DriveIntent(index: DriveIndex(2), activation: 0.2),
            DriveIntent(index: DriveIndex(3), activation: 0.2),
        ]
        let corrections = try [
            ReflexCorrection(driveIndex: DriveIndex(0), clampMultiplier: 0.9, damping: 0.05, delta: 0.0)
        ]
        return .driveIntents(drives, corrections: corrections)
    }

    mutating func consumeCutObservabilityEvents() -> CutObservabilityEvents {
        defer { pending = CutObservabilityEvents() }
        return pending
    }
}
