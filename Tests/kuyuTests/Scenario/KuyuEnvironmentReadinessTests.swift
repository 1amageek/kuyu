import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import Testing
@testable import KuyuMLX

@MainActor
@Test(.timeLimit(.minutes(1))) func environmentReadinessMarksLiftTeacherReady() async throws {
    let artifactRoot = try temporaryReadinessRoot("lift-ready")
    let report = try await ReferenceQuadrotorEnvironmentReadinessChecker().check(
        tasks: [.lift],
        parameters: .baseline,
        schedule: try SimulationSchedule.baseline(cutPeriodSteps: 2),
        determinism: try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline),
        gains: try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2),
        artifactRoot: artifactRoot
    )

    #expect(report.allReady)
    #expect(report.tasks.count == 1)
    let readiness = try #require(report.tasks.first)
    #expect(readiness.task == "lift")
    #expect(readiness.ready)
    #expect(readiness.suitePassed)
    #expect(readiness.score.isFinite)
    #expect(readiness.scenarioActionCoverage == 1.0)
    #expect(readiness.datasetScenarioCount == readiness.scenarioCount)

    let reportURL = artifactRoot.appendingPathComponent("environment-readiness.json")
    #expect(FileManager.default.fileExists(atPath: reportURL.path))
    let data = try Data(contentsOf: reportURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let reloaded = try decoder.decode(ReferenceQuadrotorEnvironmentReadinessReport.self, from: data)
    #expect(reloaded.allReady == report.allReady)
    #expect(reloaded.tasks == report.tasks)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func environmentReadinessMarksSingleLiftTeacherReady() async throws {
    let report = try await ReferenceQuadrotorEnvironmentReadinessChecker().check(
        tasks: [.singleLift],
        parameters: .baseline,
        schedule: try SimulationSchedule.baseline(cutPeriodSteps: 2),
        determinism: try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline),
        gains: try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2)
    )

    #expect(report.allReady)
    #expect(report.tasks.count == 1)
    let readiness = try #require(report.tasks.first)
    #expect(readiness.task == "singleLift")
    #expect(readiness.ready)
    #expect(readiness.suitePassed)
    #expect(readiness.failureCount == 0)
    #expect(readiness.scenarioActionCoverage == 1.0)
    #expect(readiness.datasetScenarioCount == readiness.scenarioCount)
    #expect(readiness.failureReasons.isEmpty)
}

private func temporaryReadinessRoot(_ name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-environment-readiness-tests", isDirectory: true)
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    if FileManager.default.fileExists(atPath: root.path) {
        try FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
