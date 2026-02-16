import Testing
import KuyuCore
import KuyuPhysics
import KuyuScenarios

@Test(.timeLimit(.minutes(1))) func plannerDegradationScenarioRunsWithoutDescendingInput() async throws {
    var cut = try DescendingProgramCut()
    let log = try await runShortScenario(cut: &cut)
    #expect(log.events.count == 10)
    #expect(log.failureReason == nil)
}

@Test(.timeLimit(.minutes(1))) func plannerDegradationScenarioRunsWithDescendingProgram() async throws {
    let program = try DescendingIntentProgram(keyframes: [
        try DescendingIntentProgram.Keyframe(time: 0.0, values: [0.20, 0.20, 0.20, 0.20]),
        try DescendingIntentProgram.Keyframe(time: 0.01, values: [0.25, 0.25, 0.25, 0.25]),
    ])
    var cut = try DescendingProgramCut(descendingProgram: program)
    let log = try await runShortScenario(cut: &cut)
    #expect(log.events.count == 10)
    #expect(log.failureReason == nil)
}

@Test func plannerExecutorBridgeRunsAtFixedRateAndHoldsOnDisconnect() throws {
    var bridge = try PlannerExecutorBridge(channelCount: 2, updatePeriod: 0.1)
    let program = try DescendingIntentProgram(keyframes: [
        try DescendingIntentProgram.Keyframe(time: 0.0, values: [0.0, 0.0]),
        try DescendingIntentProgram.Keyframe(time: 1.0, values: [1.0, -1.0]),
    ])

    let v0 = bridge.descendingVector(at: 0.0, program: program)
    let v1 = bridge.descendingVector(at: 0.05, program: nil)
    let v2 = bridge.descendingVector(at: 0.10, program: nil)
    let v3 = bridge.descendingVector(at: 0.20, program: program)

    #expect(v0 == [0.0, 0.0])
    #expect(v1 == [0.0, 0.0])
    #expect(v2 == [0.0, 0.0])
    #expect(v3[0] > 0.0)
    #expect(v3[1] < 0.0)
}

private func runShortScenario(cut: inout DescendingProgramCut) async throws -> SimulationLog {
    let timeStep = try TimeStep(delta: 0.001)
    let config = try ScenarioConfig(
        id: ScenarioID("PLANNER-DEGRADATION"),
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
    let runner = ReferenceQuadrotorScenarioRunner<DescendingProgramCut, FixedQuadMotorNerve>(
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

    return try await runner.runScenario(
        definition: definition,
        cut: cut,
        motorNerve: motorNerve
    )
}

private struct DescendingProgramCut: CutInterface {
    private let fixedDescendingVector: [Double]?
    private let descendingProgram: DescendingIntentProgram?
    private var bridge: PlannerExecutorBridge

    init(
        fixedDescendingVector: [Double]? = nil,
        descendingProgram: DescendingIntentProgram? = nil
    ) throws {
        self.fixedDescendingVector = fixedDescendingVector
        self.descendingProgram = descendingProgram
        bridge = try PlannerExecutorBridge(channelCount: 4, updatePeriod: 0.001, clampRange: 0.0...1.0)
    }

    mutating func update(samples: [ChannelSample], time: WorldTime) throws -> CutOutput {
        let normalized: [Double]
        if let descendingProgram {
            normalized = bridge.descendingVector(at: time.time, program: descendingProgram)
        } else {
            normalized = normalizedDescending(fixedDescendingVector ?? [], targetSize: 4)
        }
        let intents = try normalized.enumerated().map { index, value in
            try DriveIntent(index: DriveIndex(UInt32(index)), activation: value)
        }
        return .driveIntents(intents, corrections: [])
    }

    private func normalizedDescending(_ raw: [Double], targetSize: Int) -> [Double] {
        var values = raw.prefix(targetSize).map { value -> Double in
            guard value.isFinite else { return 0.0 }
            return min(max(value, 0.0), 1.0)
        }
        if values.count < targetSize {
            values.append(contentsOf: [Double](repeating: 0.0, count: targetSize - values.count))
        }
        return values
    }
}
