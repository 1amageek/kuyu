import KuyuCore

public struct SinglePropHoverCut: CutInterface {
    public enum CutError: Error, Equatable {
        case invalidHoverThrust
        case invalidMaxThrust
        case invalidTargetZ
    }

    public var targetZ: Double
    public var hoverThrust: Double
    public var maxThrust: Double
    public var kp: Double
    public var kd: Double

    private var altitudeZ: Double
    private var velocityZ: Double

    public init(
        targetZ: Double,
        hoverThrust: Double,
        maxThrust: Double,
        kp: Double = 6.0,
        kd: Double = 4.0
    ) throws {
        guard targetZ.isFinite else { throw CutError.invalidTargetZ }
        guard hoverThrust.isFinite else { throw CutError.invalidHoverThrust }
        guard maxThrust > 0, maxThrust.isFinite else { throw CutError.invalidMaxThrust }
        self.targetZ = targetZ
        self.hoverThrust = hoverThrust
        self.maxThrust = maxThrust
        self.kp = kp
        self.kd = kd
        self.altitudeZ = 0
        self.velocityZ = 0
    }

    public mutating func update(samples: [ChannelSample], time: WorldTime) throws -> CutOutput {
        _ = time
        for sample in samples {
            switch sample.channelIndex {
            case 6:
                altitudeZ = sample.value
            case 7:
                velocityZ = sample.value
            default:
                break
            }
        }

        let error = targetZ - altitudeZ
        let desiredThrust = hoverThrust + kp * error - kd * velocityZ
        let clampedThrust = clamp(desiredThrust, lower: 0.0, upper: maxThrust)
        let throttle = clamp(clampedThrust / max(maxThrust, 1e-6), lower: 0.0, upper: 1.0)

        let drives = try [DriveIntent(index: DriveIndex(0), activation: throttle)]
        return .driveIntents(drives, corrections: [])
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
