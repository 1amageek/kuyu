import Testing
import KuyuScenarios

@Test func episodicMemoryStoreSupportsTaskMorphologyScenarioSeedQuery() throws {
    var store = EpisodicMemoryStore()
    store.append(
        EpisodicMemoryRecord(
            key: EpisodicMemoryKey(task: "hover", morphology: "quad", scenarioId: "S1", seed: 1),
            descendingContext: [0.1, 0.2]
        )
    )
    store.append(
        EpisodicMemoryRecord(
            key: EpisodicMemoryKey(task: "hover", morphology: "singleprop", scenarioId: "S2", seed: 2),
            descendingContext: [0.3]
        )
    )

    let byTask = store.query(task: "hover")
    #expect(byTask.count == 2)

    let byMorphology = store.query(morphology: "quad")
    #expect(byMorphology.count == 1)
    #expect(byMorphology.first?.key.scenarioId == "S1")

    let byScenarioSeed = store.query(scenarioId: "S2", seed: 2)
    #expect(byScenarioSeed.count == 1)
    #expect(byScenarioSeed.first?.key.morphology == "singleprop")
}

@Test func episodicMemoryBoundaryProjectsOnlyDescendingContext() throws {
    let records = [
        EpisodicMemoryRecord(
            key: EpisodicMemoryKey(task: "recover", morphology: "quad", scenarioId: "S3", seed: 7),
            descendingContext: [0.9, .nan, -0.2]
        )
    ]

    let projected = EpisodicMemoryBoundary.descendingVector(from: records, channelCount: 5)
    #expect(projected.count == 5)
    #expect(projected[0] == 0.9)
    #expect(projected[1] == 0.0)
    #expect(projected[2] == -0.2)
    #expect(projected[3] == 0.0)
    #expect(projected[4] == 0.0)
}

@Test func episodicMemoryBoundaryReturnsNeutralVectorWhenNoRecall() throws {
    let projected = EpisodicMemoryBoundary.descendingVector(from: [], channelCount: 3)
    #expect(projected == [0.0, 0.0, 0.0])
}
