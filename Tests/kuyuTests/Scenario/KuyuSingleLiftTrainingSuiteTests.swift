import KuyuCore
import KuyuPhysics
import KuyuScenarios
import Testing
@testable import KuyuMLX

@Test func singleLiftTrainingSuiteAddsBalancedAltitudeOffsets() throws {
    let scenarios = try KuyuSingleLiftTrainingSuite().scenarios()

    #expect(scenarios.count == 13)
    let altitudes = scenarios.map(\.initialPosition.z)
    #expect(altitudes.contains(0.25))
    #expect(altitudes.contains(0.5))
    #expect(altitudes.contains(0.75))
    #expect(altitudes.filter { $0 == 0.5 }.count == 3)
    #expect(scenarios.allSatisfy { $0.kind == .singleLiftHover })
}

@MainActor
@Test(.timeLimit(.minutes(1))) func singleLiftTrainingDatasetRunnerPassesTeacherSuite() async throws {
    let output = try await KuyuSingleLiftTeacherDatasetRunner().run(
        request: SimulationRunRequest(
            controller: .teacherBaseline,
            taskMode: .singleLift,
            gains: try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2),
            cutPeriodSteps: 2,
            noise: .zero,
            determinism: try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline),
            modelDescriptorPath: "",
            overrideParameters: nil,
            useAux: true,
            useQualityGating: true
        ),
        parameters: .baseline,
        schedule: try SimulationSchedule.baseline(cutPeriodSteps: 2)
    )

    #expect(output.summary.suitePassed)
    #expect(output.summary.evaluations.count == 13)
    #expect(output.logs.count == 13)
    #expect(output.logs.allSatisfy { entry in
        entry.log.events.contains { !$0.driveIntents.isEmpty }
    })
}
