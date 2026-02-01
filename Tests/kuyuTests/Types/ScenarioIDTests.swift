import Testing
@testable import kuyu

@Test(.timeLimit(.minutes(1))) func scenarioIDRejectsEmpty() async throws {
    do {
        _ = try ScenarioID("")
        #expect(Bool(false))
    } catch let error as ScenarioID.ValidationError {
        #expect(error == .empty)
    }
}

@Test(.timeLimit(.minutes(1))) func scenarioIDAcceptsNonEmpty() async throws {
    let id = try ScenarioID("KUY-ATT-1/SCN-1")
    #expect(id.rawValue == "KUY-ATT-1/SCN-1")
}
