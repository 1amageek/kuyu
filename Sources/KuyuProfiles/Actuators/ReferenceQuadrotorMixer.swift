import simd
import KuyuCore

public struct ReferenceQuadrotorMixer: Sendable, Equatable {
    public enum Layout: String, Sendable, Codable {
        case plus
    }

    public let armLength: Double
    public let yawCoefficient: Double
    public let layout: Layout
    public let spinDirections: SIMD4<Double>

    public init(
        armLength: Double,
        yawCoefficient: Double,
        layout: Layout = .plus,
        spinDirections: SIMD4<Double> = SIMD4<Double>(1, -1, 1, -1)
    ) {
        self.armLength = armLength
        self.yawCoefficient = yawCoefficient
        self.layout = layout
        self.spinDirections = spinDirections
    }

    public func mix(thrusts: MotorThrusts) -> (forceBody: SIMD3<Double>, torqueBody: SIMD3<Double>) {
        let f1 = thrusts.f1
        let f2 = thrusts.f2
        let f3 = thrusts.f3
        let f4 = thrusts.f4

        let totalForce = f1 + f2 + f3 + f4
        let forceBody = SIMD3<Double>(0, 0, totalForce)

        let tauX = armLength * (f2 - f4)
        let tauY = armLength * (f3 - f1)
        let tauZ = yawCoefficient * (spinDirections.x * f1 + spinDirections.y * f2 + spinDirections.z * f3 + spinDirections.w * f4)

        return (forceBody, SIMD3<Double>(tauX, tauY, tauZ))
    }
}
