import simd
import KuyuCore

public struct EulerAngles: Sendable, Codable, Equatable {
    public let roll: Double
    public let pitch: Double
    public let yaw: Double

    public init(roll: Double, pitch: Double, yaw: Double) {
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
    }

    public static func degrees(roll: Double, pitch: Double, yaw: Double) -> EulerAngles {
        let toRad = Double.pi / 180.0
        return EulerAngles(roll: roll * toRad, pitch: pitch * toRad, yaw: yaw * toRad)
    }

    public func toQuaternion() -> simd_quatd {
        let qx = simd_quatd(angle: roll, axis: SIMD3<Double>(1, 0, 0))
        let qy = simd_quatd(angle: pitch, axis: SIMD3<Double>(0, 1, 0))
        let qz = simd_quatd(angle: yaw, axis: SIMD3<Double>(0, 0, 1))
        return (qz * qy * qx).normalizedQuat
    }
}
