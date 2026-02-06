import KuyuCore

public struct ActuatorDegradation: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case nonPositive(String)
    }

    public let startTime: Double
    public let motorIndex: UInt32
    public let maxThrustScale: Double

    public init(startTime: Double, motorIndex: UInt32, maxThrustScale: Double) throws {
        guard startTime.isFinite else { throw ValidationError.nonFinite("startTime") }
        guard maxThrustScale.isFinite else { throw ValidationError.nonFinite("maxThrustScale") }
        guard maxThrustScale > 0 else { throw ValidationError.nonPositive("maxThrustScale") }

        self.startTime = startTime
        self.motorIndex = motorIndex
        self.maxThrustScale = maxThrustScale
    }
}
