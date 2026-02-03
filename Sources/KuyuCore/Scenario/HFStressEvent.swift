public struct HFStressEvent: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable, Equatable {
        case impulse
        case vibration
        case sensorGlitch
        case actuatorSaturation
        case latencySpike
    }

    public enum ValidationError: Error, Equatable {
        case nonFinite
        case negative
    }

    public let kind: Kind
    public let startTime: Double
    public let duration: Double
    public let magnitude: Double

    public init(kind: Kind, startTime: Double, duration: Double, magnitude: Double) throws {
        guard startTime.isFinite, duration.isFinite, magnitude.isFinite else {
            throw ValidationError.nonFinite
        }
        guard startTime >= 0, duration >= 0 else {
            throw ValidationError.negative
        }
        self.kind = kind
        self.startTime = startTime
        self.duration = duration
        self.magnitude = magnitude
    }
}
