import Testing
import KuyuCore
import KuyuMLX

private struct MockAnalyticalState: AnalyticalState {
    let values: [Float]

    var dimensions: Int { values.count }

    func toArray() -> [Float] {
        values
    }

    func toPlantStateSnapshot() -> PlantStateSnapshot {
        PlantStateSnapshot(
            root: RigidBodySnapshot(
                id: "root",
                position: Axis3(x: 0, y: 0, z: 0),
                velocity: Axis3(x: 0, y: 0, z: 0),
                orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
                angularVelocity: Axis3(x: 0, y: 0, z: 0)
            )
        )
    }
}

@Test func ascendingChannelMapperMapsMultisourceInputsToTypedAscendingChannels() throws {
    let mapper = AscendingChannelMapper()
    let fused = FusedState(
        physics: MockAnalyticalState(values: [1.0, 2.0]),
        worldModelOutput: try WorldModelOutput(
            residual: [0.1, -0.1],
            extensions: [0.5],
            uncertainty: [0.2, 0.2, 0.3]
        )
    )
    let samples = [
        try ChannelSample(channelIndex: 0, value: 0.8, timestamp: 0.0),
        try ChannelSample(channelIndex: 1, value: -0.2, timestamp: 0.0),
    ]

    let channels = mapper.map(fusedState: fused, sensorSamples: samples)
    #expect(channels.sensor == [0.8, -0.2])
    #expect(channels.physics == [1.0, 2.0])
    #expect(channels.residual == [0.1, -0.1])
    #expect(channels.extensions == [0.5])
    #expect(channels.totalCount == 7)
    #expect(channels.typeIndices.count == 7)
}

@Test func ascendingChannelMapperPhysicsOnlyPathKeepsAdapterBoundary() throws {
    let mapper = AscendingChannelMapper()
    let samples = [try ChannelSample(channelIndex: 0, value: 0.5, timestamp: 0.0)]
    let channels = mapper.mapPhysicsOnly(
        physicsState: MockAnalyticalState(values: [3.0, 4.0]),
        sensorSamples: samples
    )

    #expect(channels.sensor == [0.5])
    #expect(channels.physics == [3.0, 4.0])
    #expect(channels.residual == [0.0, 0.0])
    #expect(channels.extensions.isEmpty)
}
