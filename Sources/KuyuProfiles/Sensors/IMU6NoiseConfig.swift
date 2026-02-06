import KuyuCore

public struct IMU6NoiseConfig: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case negative(String)
    }

    public let gyroNoiseStdDev: Double
    public let gyroBias: Double
    public let gyroRandomWalkSigma: Double
    public let accelNoiseStdDev: Double
    public let accelBias: Double
    public let accelRandomWalkSigma: Double
    public let delaySteps: UInt64

    public init(
        gyroNoiseStdDev: Double,
        gyroBias: Double,
        gyroRandomWalkSigma: Double,
        accelNoiseStdDev: Double,
        accelBias: Double,
        accelRandomWalkSigma: Double,
        delaySteps: UInt64
    ) throws {
        guard gyroNoiseStdDev.isFinite else { throw ValidationError.nonFinite("gyroNoiseStdDev") }
        guard gyroBias.isFinite else { throw ValidationError.nonFinite("gyroBias") }
        guard gyroRandomWalkSigma.isFinite else { throw ValidationError.nonFinite("gyroRandomWalkSigma") }
        guard accelNoiseStdDev.isFinite else { throw ValidationError.nonFinite("accelNoiseStdDev") }
        guard accelBias.isFinite else { throw ValidationError.nonFinite("accelBias") }
        guard accelRandomWalkSigma.isFinite else { throw ValidationError.nonFinite("accelRandomWalkSigma") }

        guard gyroNoiseStdDev >= 0 else { throw ValidationError.negative("gyroNoiseStdDev") }
        guard gyroRandomWalkSigma >= 0 else { throw ValidationError.negative("gyroRandomWalkSigma") }
        guard accelNoiseStdDev >= 0 else { throw ValidationError.negative("accelNoiseStdDev") }
        guard accelRandomWalkSigma >= 0 else { throw ValidationError.negative("accelRandomWalkSigma") }

        self.gyroNoiseStdDev = gyroNoiseStdDev
        self.gyroBias = gyroBias
        self.gyroRandomWalkSigma = gyroRandomWalkSigma
        self.accelNoiseStdDev = accelNoiseStdDev
        self.accelBias = accelBias
        self.accelRandomWalkSigma = accelRandomWalkSigma
        self.delaySteps = delaySteps
    }

    public static let zero: IMU6NoiseConfig = {
        do {
            return try IMU6NoiseConfig(
                gyroNoiseStdDev: 0,
                gyroBias: 0,
                gyroRandomWalkSigma: 0,
                accelNoiseStdDev: 0,
                accelBias: 0,
                accelRandomWalkSigma: 0,
                delaySteps: 0
            )
        } catch {
            preconditionFailure("Invalid zero IMU noise config: \(error)")
        }
    }()
}
