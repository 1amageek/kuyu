public struct ActuatorSwapEvent: Sendable, Codable, Equatable {
    public enum SwapKind: String, Sendable, Codable, Equatable {
        case swapUnit
        case gainShift
        case lagShift
        case maxOutputShift
        case deadzoneShift
    }

    public enum ValidationError: Error, Equatable {
        case nonFinite
        case negative
    }

    public let kind: SwapKind
    public let startTime: Double
    public let duration: Double
    public let motorIndex: UInt32
    public let gainScale: Double
    public let lagScale: Double
    public let maxOutputScale: Double
    public let deadzoneShift: Double

    public init(
        kind: SwapKind,
        startTime: Double,
        duration: Double,
        motorIndex: UInt32,
        gainScale: Double,
        lagScale: Double,
        maxOutputScale: Double,
        deadzoneShift: Double
    ) throws {
        guard startTime.isFinite, duration.isFinite, gainScale.isFinite,
              lagScale.isFinite, maxOutputScale.isFinite, deadzoneShift.isFinite else {
            throw ValidationError.nonFinite
        }
        guard startTime >= 0, duration >= 0, gainScale > 0, lagScale > 0, maxOutputScale > 0 else {
            throw ValidationError.negative
        }
        self.kind = kind
        self.startTime = startTime
        self.duration = duration
        self.motorIndex = motorIndex
        self.gainScale = gainScale
        self.lagScale = lagScale
        self.maxOutputScale = maxOutputScale
        self.deadzoneShift = deadzoneShift
    }
}
