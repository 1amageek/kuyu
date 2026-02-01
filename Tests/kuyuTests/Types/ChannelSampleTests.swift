import Testing
@testable import kuyu

@Test(.timeLimit(.minutes(1))) func channelSampleRejectsNegativeTimestamp() async throws {
    do {
        _ = try ChannelSample(channelIndex: 0, value: 0.0, timestamp: -0.1)
        #expect(Bool(false))
    } catch let error as ChannelSample.ValidationError {
        #expect(error == .negativeTimestamp)
    }
}

@Test(.timeLimit(.minutes(1))) func channelSampleRejectsNonFiniteValue() async throws {
    do {
        _ = try ChannelSample(channelIndex: 0, value: .infinity, timestamp: 0.0)
        #expect(Bool(false))
    } catch let error as ChannelSample.ValidationError {
        #expect(error == .nonFiniteValue)
    }
}

@Test(.timeLimit(.minutes(1))) func channelSampleAcceptsValid() async throws {
    let sample = try ChannelSample(channelIndex: 2, value: 1.25, timestamp: 0.5)
    #expect(sample.channelIndex == 2)
    #expect(sample.value == 1.25)
    #expect(sample.timestamp == 0.5)
}
