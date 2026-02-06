import Foundation
import KuyuCore

public struct AxisNoiseModel: Sendable {
    public var bias: Double
    public let randomWalkSigma: Double
    private var noise: GaussianNoise
    private var walkNoise: GaussianNoise

    public init(
        bias: Double,
        noiseStdDev: Double,
        randomWalkSigma: Double,
        seed: UInt64
    ) {
        self.bias = bias
        self.randomWalkSigma = randomWalkSigma
        self.noise = GaussianNoise(stdDev: noiseStdDev, seed: seed &+ 0x9E3779B97F4A7C15)
        self.walkNoise = GaussianNoise(stdDev: 1.0, seed: seed ^ 0xBF58476D1CE4E5B9)
    }

    public mutating func sample(delta: TimeInterval) -> Double {
        if randomWalkSigma > 0 {
            let step = walkNoise.sample() * randomWalkSigma * sqrt(delta)
            bias += step
        }
        return bias + noise.sample()
    }
}
