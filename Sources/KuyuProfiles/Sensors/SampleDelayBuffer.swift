import KuyuCore

public struct SampleDelayBuffer: Sendable {
    public let delaySteps: UInt64
    private var queue: [[ChannelSample]]

    public init(delaySteps: UInt64) {
        self.delaySteps = delaySteps
        self.queue = []
        self.queue.reserveCapacity(Int(delaySteps) + 1)
    }

    public mutating func push(_ samples: [ChannelSample]) -> [ChannelSample] {
        if delaySteps == 0 {
            return samples
        }

        queue.append(samples)
        if queue.count > Int(delaySteps) {
            return queue.removeFirst()
        }
        return []
    }
}
