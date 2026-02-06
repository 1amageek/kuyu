import Foundation
import KuyuCore

public struct GaussianNoise: Sendable {
    public var stdDev: Double
    private var rng: SplitMix64
    private var spare: Double?

    public init(stdDev: Double, seed: UInt64) {
        self.stdDev = stdDev
        self.rng = SplitMix64(seed: seed)
        self.spare = nil
    }

    public mutating func sample() -> Double {
        if let spare {
            self.spare = nil
            return spare * stdDev
        }

        let u1 = max(rng.nextDouble(), Double.leastNonzeroMagnitude)
        let u2 = rng.nextDouble()
        let radius = sqrt(-2.0 * log(u1))
        let theta = 2.0 * Double.pi * u2
        let z0 = radius * cos(theta)
        let z1 = radius * sin(theta)
        spare = z1
        return z0 * stdDev
    }
}
