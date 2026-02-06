import KuyuCore

public struct SinglePropLiftCut: CutInterface {
    public enum CutError: Error, Equatable {
        case invalidHoverThrust
        case invalidMaxThrust
    }

    public var hoverThrust: Double
    public var maxThrust: Double
    public var fallAccelThreshold: Double
    public var fallThrustBoost: Double

    private var accelZ: Double

    public init(
        hoverThrust: Double,
        maxThrust: Double,
        fallAccelThreshold: Double = 0.35,
        fallThrustBoost: Double = 0.15
    ) throws {
        guard hoverThrust.isFinite else { throw CutError.invalidHoverThrust }
        guard maxThrust > 0, maxThrust.isFinite else { throw CutError.invalidMaxThrust }
        self.hoverThrust = hoverThrust
        self.maxThrust = maxThrust
        self.fallAccelThreshold = fallAccelThreshold
        self.fallThrustBoost = fallThrustBoost
        self.accelZ = 0
    }

    public mutating func update(samples: [ChannelSample], time: WorldTime) throws -> CutOutput {
        _ = time
        for sample in samples where sample.channelIndex == 5 {
            accelZ = sample.value
        }

        let accelMag = max(1e-6, abs(accelZ))
        let fallFactor = clamp((fallAccelThreshold - accelMag) / max(fallAccelThreshold, 1e-6), lower: 0, upper: 1)
        let totalThrust = hoverThrust * (1.0 + fallFactor * fallThrustBoost)
        let throttle = clamp(totalThrust / max(maxThrust, 1e-6), lower: 0.0, upper: 1.0)

        let drives = try [DriveIntent(index: DriveIndex(0), activation: throttle)]
        return .driveIntents(drives, corrections: [])
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
