import KuyuCore

public struct ImuRateDampingCutGains: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case negative(String)
    }

    public let kp: Double
    public let kd: Double
    public let yawDamping: Double
    public let hoverThrustScale: Double

    public init(kp: Double, kd: Double, yawDamping: Double, hoverThrustScale: Double = 1.0) throws {
        guard kp.isFinite else { throw ValidationError.nonFinite("kp") }
        guard kd.isFinite else { throw ValidationError.nonFinite("kd") }
        guard yawDamping.isFinite else { throw ValidationError.nonFinite("yawDamping") }
        guard hoverThrustScale.isFinite else { throw ValidationError.nonFinite("hoverThrustScale") }

        guard kp >= 0 else { throw ValidationError.negative("kp") }
        guard kd >= 0 else { throw ValidationError.negative("kd") }
        guard yawDamping >= 0 else { throw ValidationError.negative("yawDamping") }
        guard hoverThrustScale > 0 else { throw ValidationError.negative("hoverThrustScale") }

        self.kp = kp
        self.kd = kd
        self.yawDamping = yawDamping
        self.hoverThrustScale = hoverThrustScale
    }
}
