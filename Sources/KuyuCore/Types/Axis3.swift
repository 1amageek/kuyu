import simd

public struct Axis3: Sendable, Codable, Equatable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var simd: SIMD3<Double> {
        SIMD3<Double>(x, y, z)
    }
}
