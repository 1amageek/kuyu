import simd

public struct DisturbanceState: Sendable, Equatable {
    public var torqueBody: SIMD3<Double>
    public var forceWorld: SIMD3<Double>

    public init(torqueBody: SIMD3<Double>, forceWorld: SIMD3<Double>) {
        self.torqueBody = torqueBody
        self.forceWorld = forceWorld
    }

    public static let zero = DisturbanceState(
        torqueBody: SIMD3<Double>(repeating: 0),
        forceWorld: SIMD3<Double>(repeating: 0)
    )

    public func torqueAxis3() -> Axis3 {
        Axis3(x: torqueBody.x, y: torqueBody.y, z: torqueBody.z)
    }

    public func forceAxis3() -> Axis3 {
        Axis3(x: forceWorld.x, y: forceWorld.y, z: forceWorld.z)
    }
}
