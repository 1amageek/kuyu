import Testing
@testable import kuyu

@Test(.timeLimit(.minutes(1))) func motorMaxThrustsUniformAndSetting() async throws {
    let maxes = try MotorMaxThrusts.uniform(5.0)
    #expect(maxes.max(forIndex: 0) == 5.0)
    #expect(maxes.max(forIndex: 3) == 5.0)

    let updated = try maxes.setting(index: 2, value: 2.5)
    #expect(updated.max(forIndex: 2) == 2.5)
    #expect(updated.max(forIndex: 1) == 5.0)
}
