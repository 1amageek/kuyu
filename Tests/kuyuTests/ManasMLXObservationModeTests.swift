import KuyuCore
import Testing
@testable import KuyuMLX

@Test func singleLiftRuntimeUsesExtendedObservationMode() throws {
    let mode = ManasMLXObservationMode.runtimeMode(for: .singleLift)
    #expect(mode == .passThrough(channelCount: 8))
    #expect(mode.accepts(channelIndex: 6))
    #expect(mode.accepts(channelIndex: 7))
    #expect(!mode.accepts(channelIndex: 8))
}

@Test func liftRuntimeUsesExtendedObservationMode() throws {
    let mode = ManasMLXObservationMode.runtimeMode(for: .lift)
    #expect(mode == .passThrough(channelCount: 64))
    #expect(mode.accepts(channelIndex: 0))
    #expect(mode.accepts(channelIndex: 63))
    #expect(!mode.accepts(channelIndex: 64))
}

@Test func singleDriveDatasetsKeepAltitudeObservationChannels() throws {
    let mode = ManasMLXObservationMode.trainingMode(channelCount: 8, driveCount: 1)
    #expect(mode == .passThrough(channelCount: 8))
}

@Test func multiDriveDatasetsKeepAltitudeObservationChannels() throws {
    let mode = ManasMLXObservationMode.trainingMode(channelCount: 8, driveCount: 4)
    #expect(mode == .passThrough(channelCount: 8))
}

@Test func checkpointInputSizeRestoresObservationMode() throws {
    #expect(ManasMLXObservationMode.checkpointMode(coreInputSize: 24) == .imu6)
    #expect(ManasMLXObservationMode.checkpointMode(coreInputSize: 32) == .passThrough(channelCount: 8))
    #expect(ManasMLXObservationMode.checkpointMode(coreInputSize: 256) == .passThrough(channelCount: 64))
}

@Test func extendedObservationModeProducesLargerTrunkSize() throws {
    let imuSizing = try ManasMLXCut.computeSizing(observationMode: .imu6, useQualityGating: true)
    let extendedSizing = try ManasMLXCut.computeSizing(
        observationMode: .passThrough(channelCount: 8),
        useQualityGating: true
    )

    #expect(imuSizing.trunkSize == 24)
    #expect(imuSizing.fastTapCount == 6)
    #expect(extendedSizing.trunkSize == 32)
    #expect(extendedSizing.fastTapCount == 8)
}
