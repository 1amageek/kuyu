import Testing
@testable import kuyu

@Test(.timeLimit(.minutes(1))) func kuyAtt1SuiteBuildsExpectedDefinitions() async throws {
    let suite = KuyAtt1Suite()
    let definitions = try suite.scenarios()
    #expect(definitions.count == 15)

    let durations = Set(definitions.map { $0.config.duration })
    #expect(durations.count == 1)
    #expect(durations.first == 20.0)

    let steps = Set(definitions.map { $0.config.timeStep.delta })
    #expect(steps.count == 1)
    #expect(steps.first == 0.001)

    let kinds = Dictionary(grouping: definitions, by: { $0.kind })
    #expect(kinds[.hoverStart]?.count == 3)
    #expect(kinds[.impulseTorqueShock]?.count == 3)
    #expect(kinds[.sustainedWindTorque]?.count == 3)
    #expect(kinds[.sensorDriftStress]?.count == 3)
    #expect(kinds[.actuatorDegradation]?.count == 3)
}
