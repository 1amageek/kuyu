import simd

public struct QuaternionSnapshot: Sendable, Codable, Equatable {
    public let w: Double
    public let x: Double
    public let y: Double
    public let z: Double

    public init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    public init(orientation: simd_quatd) {
        let q = orientation.normalizedQuat
        self.init(w: q.vector.w, x: q.vector.x, y: q.vector.y, z: q.vector.z)
    }

    public func dot(_ other: QuaternionSnapshot) -> Double {
        w * other.w + x * other.x + y * other.y + z * other.z
    }
}
