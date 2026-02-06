import simd

public struct SafetyTrace: Sendable, Codable, Equatable {
    public let omegaMagnitude: Double
    public let tiltRadians: Double

    public init(omegaMagnitude: Double, tiltRadians: Double) {
        self.omegaMagnitude = omegaMagnitude
        self.tiltRadians = tiltRadians
    }

    public init(root: RigidBodySnapshot) {
        let omegaMagnitude = simd_length(root.angularVelocity.simd)
        let bodyZ = root.orientation.act(SIMD3<Double>(0, 0, 1))
        let dot = max(-1.0, min(1.0, simd_dot(bodyZ, SIMD3<Double>(0, 0, 1))))
        let tilt = acos(dot)
        self.init(omegaMagnitude: omegaMagnitude, tiltRadians: tilt)
    }
}
