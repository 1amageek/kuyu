import Testing
import KuyuCore
import KuyuPhysics
import KuyuScenarios

@MainActor
@Test(.timeLimit(.minutes(1))) func kuyAtt1BaselineModesSeparateTeacherFromSensorOnlyControl() async throws {
    #expect(ControllerSelection.allCases.contains(.teacherActiveAltitudeHold))
    #expect(ControllerSelection.allCases.contains(.sensorBaseline))
    #expect(ControllerSelection.teacherActiveAltitudeHold.kuyAtt1BaselineMode == .teacher)
    #expect(ControllerSelection.sensorBaseline.kuyAtt1BaselineMode == .sensor)

    let gains = try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2, hoverThrustScale: 1.0)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: 2)
    let factoryTeacher = try KuyAtt1Runner.activeAltitudeHoldTeacher(gains: gains)

    #expect(factoryTeacher.baselineMode == .teacher)

    let teacher = KuyAtt1Runner(
        schedule: schedule,
        determinism: .tier1Baseline,
        noise: .zero,
        gains: gains,
        baselineMode: .teacher
    )
    let sensor = KuyAtt1Runner(
        schedule: schedule,
        determinism: .tier1Baseline,
        noise: .zero,
        gains: gains,
        baselineMode: .sensor
    )

    let teacherOutput = try await teacher.runWithLogs()
    let sensorOutput = try await sensor.runWithLogs()

    #expect(teacherOutput.summary.suitePassed)
    #expect(!sensorOutput.summary.suitePassed)
    #expect(teacherOutput.logs.count == teacherOutput.summary.manifest.count)
    #expect(sensorOutput.logs.count == sensorOutput.summary.manifest.count)
    #expect(teacherOutput.result.replay.notPerformedReason != nil)
    #expect(sensorOutput.result.replay.notPerformedReason == nil)
    #expect(sensorOutput.result.replay.checks.count == sensorOutput.logs.count)
    #expect(sensorOutput.result.replay.checks.allSatisfy { $0.passed })
}
