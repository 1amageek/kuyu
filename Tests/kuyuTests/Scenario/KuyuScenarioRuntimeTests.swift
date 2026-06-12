import KuyuCore
import KuyuPhysics
import KuyuScenarios
import Testing
@testable import KuyuMLX

@MainActor
@Test(.timeLimit(.minutes(1))) func nonUIScenarioRuntimeRunsLiftTeacherSuite() async throws {
    let output = try await ReferenceQuadrotorScenarioRuntime(modelStore: ManasMLXModelStore()).run(
        request: SimulationRunRequest(
            controller: .teacherActiveAltitudeHold,
            taskMode: .lift,
            gains: try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2),
            cutPeriodSteps: 2,
            noise: .zero,
            determinism: try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline),
            robotManifestPath: "",
            overrideParameters: nil,
            useAux: true,
            useQualityGating: true
        ),
        parameters: .baseline,
        schedule: try SimulationSchedule.baseline(cutPeriodSteps: 2),
        embodiment: nil
    )

    #expect(!output.logs.isEmpty)
    #expect(output.summary.manifest.count == output.logs.count)
    #expect(output.logs.contains { entry in
        entry.log.events.contains { !$0.driveIntents.isEmpty || !$0.actuatorValues.isEmpty }
    })
}

@MainActor
@Test(.timeLimit(.minutes(1))) func nonUIScenarioRuntimeRunsSingleLiftTeacherSuite() async throws {
    let output = try await ReferenceQuadrotorScenarioRuntime(modelStore: ManasMLXModelStore()).run(
        request: SimulationRunRequest(
            controller: .teacherActiveAltitudeHold,
            taskMode: .singleLift,
            gains: try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2),
            cutPeriodSteps: 2,
            noise: .zero,
            determinism: try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline),
            robotManifestPath: "",
            overrideParameters: nil,
            useAux: true,
            useQualityGating: true
        ),
        parameters: .baseline,
        schedule: try SimulationSchedule.baseline(cutPeriodSteps: 2),
        embodiment: nil
    )

    #expect(!output.logs.isEmpty)
    #expect(output.summary.manifest.count == output.logs.count)
    #expect(output.logs.contains { entry in
        entry.log.events.contains { !$0.driveIntents.isEmpty || !$0.actuatorValues.isEmpty }
    })
}
