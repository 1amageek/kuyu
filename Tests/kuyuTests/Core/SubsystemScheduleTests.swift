import Testing
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func subsystemScheduleIsDueOnMultiple() async throws {
    let schedule = try SubsystemSchedule(periodSteps: 2)
    #expect(schedule.isDue(stepIndex: 0))
    #expect(!schedule.isDue(stepIndex: 1))
    #expect(schedule.isDue(stepIndex: 2))
    #expect(!schedule.isDue(stepIndex: 3))
}
