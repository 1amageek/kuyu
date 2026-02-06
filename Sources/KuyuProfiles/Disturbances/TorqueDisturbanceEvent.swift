import simd
import KuyuCore

public struct TorqueDisturbanceEvent: Sendable, Equatable, Codable {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case negative(String)
    }

    public let startTime: Double
    public let duration: Double
    public let torqueBody: Axis3

    public init(startTime: Double, duration: Double, torqueBody: Axis3) throws {
        guard startTime.isFinite else { throw ValidationError.nonFinite("startTime") }
        guard duration.isFinite else { throw ValidationError.nonFinite("duration") }
        guard duration >= 0 else { throw ValidationError.negative("duration") }

        self.startTime = startTime
        self.duration = duration
        self.torqueBody = torqueBody
    }

    public func isActive(at time: Double) -> Bool {
        time >= startTime && time <= (startTime + duration)
    }

    public var torqueSIMD: SIMD3<Double> {
        SIMD3<Double>(torqueBody.x, torqueBody.y, torqueBody.z)
    }
}
