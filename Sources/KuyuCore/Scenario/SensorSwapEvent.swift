public struct SensorSwapEvent: Sendable, Codable, Equatable {
    public enum SwapKind: String, Sendable, Codable, Equatable {
        case swapUnit
        case calibShift
        case driftChange
        case dropoutBurst
        case latencyChange
    }

    public enum ValidationError: Error, Equatable {
        case nonFinite
        case negative
    }

    public let kind: SwapKind
    public let startTime: Double
    public let duration: Double
    public let targetChannels: [UInt32]
    public let gainScale: Double
    public let biasShift: Double
    public let noiseScale: Double
    public let dropoutProbability: Double
    public let delayShiftSteps: Int

    public init(
        kind: SwapKind,
        startTime: Double,
        duration: Double,
        targetChannels: [UInt32],
        gainScale: Double,
        biasShift: Double,
        noiseScale: Double,
        dropoutProbability: Double,
        delayShiftSteps: Int
    ) throws {
        guard startTime.isFinite, duration.isFinite, gainScale.isFinite, biasShift.isFinite,
              noiseScale.isFinite, dropoutProbability.isFinite else {
            throw ValidationError.nonFinite
        }
        guard startTime >= 0, duration >= 0, gainScale > 0, noiseScale > 0 else {
            throw ValidationError.negative
        }
        self.kind = kind
        self.startTime = startTime
        self.duration = duration
        self.targetChannels = targetChannels
        self.gainScale = gainScale
        self.biasShift = biasShift
        self.noiseScale = noiseScale
        self.dropoutProbability = min(max(dropoutProbability, 0.0), 1.0)
        self.delayShiftSteps = delayShiftSteps
    }
}
