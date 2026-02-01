import Testing
@testable import kuyu

@Test(.timeLimit(.minutes(1))) func worldTimeAdvancesStepAndTime() async throws {
    let time = try WorldTime(stepIndex: 0, time: 0.0)
    let next = try time.advanced(by: 0.1)
    #expect(next.stepIndex == 1)
    #expect(next.time == 0.1)
}

@Test(.timeLimit(.minutes(1))) func worldTimeRejectsNegative() async throws {
    do {
        _ = try WorldTime(stepIndex: 0, time: -0.1)
        #expect(Bool(false))
    } catch let error as WorldTime.ValidationError {
        #expect(error == .negative)
    }
}
