import Testing
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func timeStepRejectsNonPositive() async throws {
    do {
        _ = try TimeStep(delta: 0.0)
        #expect(Bool(false))
    } catch let error as TimeStep.ValidationError {
        #expect(error == .nonPositive)
    }
}

@Test(.timeLimit(.minutes(1))) func timeStepRejectsNonFinite() async throws {
    do {
        _ = try TimeStep(delta: .nan)
        #expect(Bool(false))
    } catch let error as TimeStep.ValidationError {
        #expect(error == .nonFinite)
    }
}

@Test(.timeLimit(.minutes(1))) func timeStepAcceptsValid() async throws {
    let step = try TimeStep(delta: 0.01)
    #expect(step.delta == 0.01)
}
