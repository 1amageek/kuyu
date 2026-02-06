import simd
import KuyuCore

public struct ImuRateDampingDriveCut: CutInterface {
    public enum CutError: Error, Equatable {
        case invalidHoverThrust
        case invalidMaxThrust
        case nonFiniteState
        case invalidMixerParameters
    }

    public var hoverThrust: Double
    public var kp: Double
    public var kd: Double
    public var yawDamping: Double
    public var armLength: Double
    public var yawCoefficient: Double
    public var maxThrust: Double
    public var rollScale: Double
    public var pitchScale: Double
    public var yawScale: Double
    public var spinDirections: SIMD4<Double>
    public var fallAccelThreshold: Double
    public var fallTiltBias: Double
    public var fallThrustBoost: Double

    private var gyro: SIMD3<Double>
    private var accel: SIMD3<Double>
    private var estimatedRoll: Double
    private var estimatedPitch: Double
    private var lastTime: Double?

    public init(
        hoverThrust: Double,
        kp: Double,
        kd: Double,
        yawDamping: Double,
        armLength: Double,
        yawCoefficient: Double,
        maxThrust: Double,
        rollScale: Double = 1.0,
        pitchScale: Double = 1.0,
        yawScale: Double = 1.0,
        spinDirections: SIMD4<Double> = SIMD4<Double>(1, -1, 1, -1),
        fallAccelThreshold: Double = 0.35,
        fallTiltBias: Double = 0.12,
        fallThrustBoost: Double = 0.15
    ) throws {
        guard hoverThrust.isFinite else { throw CutError.invalidHoverThrust }
        guard armLength > 0, yawCoefficient > 0 else { throw CutError.invalidMixerParameters }
        guard maxThrust > 0, maxThrust.isFinite else { throw CutError.invalidMaxThrust }

        self.hoverThrust = hoverThrust
        self.kp = kp
        self.kd = kd
        self.yawDamping = yawDamping
        self.armLength = armLength
        self.yawCoefficient = yawCoefficient
        self.maxThrust = maxThrust
        self.rollScale = rollScale
        self.pitchScale = pitchScale
        self.yawScale = yawScale
        self.spinDirections = spinDirections
        self.fallAccelThreshold = fallAccelThreshold
        self.fallTiltBias = fallTiltBias
        self.fallThrustBoost = fallThrustBoost
        self.gyro = SIMD3<Double>(repeating: 0)
        self.accel = SIMD3<Double>(0, 0, 1)
        self.estimatedRoll = 0
        self.estimatedPitch = 0
        self.lastTime = nil
    }

    public mutating func update(samples: [ChannelSample], time: WorldTime) throws -> CutOutput {
        for sample in samples {
            switch sample.channelIndex {
            case 0: gyro.x = sample.value
            case 1: gyro.y = sample.value
            case 2: gyro.z = sample.value
            case 3: accel.x = sample.value
            case 4: accel.y = sample.value
            case 5: accel.z = sample.value
            default: break
            }
        }

        let (roll, pitch) = estimateTilt(accel: accel)
        let (estRoll, estPitch) = updateEstimates(accelRoll: roll, accelPitch: pitch, time: time)
        let accelMag = max(1e-6, length(accel))
        let fallFactor = clamp((fallAccelThreshold - accelMag) / max(fallAccelThreshold, 1e-6), lower: 0, upper: 1)
        let rollBias = fallFactor * fallTiltBias * (accel.y / accelMag)
        let pitchBias = fallFactor * fallTiltBias * (-accel.x / accelMag)
        let desiredRoll = estRoll + rollBias
        let desiredPitch = estPitch + pitchBias

        let tauX = -kp * desiredRoll - kd * gyro.x
        let tauY = -kp * desiredPitch - kd * gyro.y
        let tauZ = -yawDamping * gyro.z

        guard tauX.isFinite, tauY.isFinite, tauZ.isFinite else { throw CutError.nonFiniteState }

        let totalThrust = hoverThrust * 4.0 * (1.0 + fallFactor * fallThrustBoost)
        let throttle = clamp(totalThrust / max(4.0 * maxThrust, 1e-6), lower: 0.0, upper: 1.0)
        let rollDenom = max(2.0 * armLength * maxThrust * rollScale, 1e-6)
        let pitchDenom = max(2.0 * armLength * maxThrust * pitchScale, 1e-6)
        let yawDenom = max(4.0 * yawCoefficient * maxThrust * yawScale, 1e-6)
        let driveRoll = clamp(tauX / rollDenom, lower: -1.0, upper: 1.0)
        let drivePitch = clamp(tauY / pitchDenom, lower: -1.0, upper: 1.0)
        let driveYaw = clamp(tauZ / yawDenom, lower: -1.0, upper: 1.0)

        let drives = try [
            DriveIntent(index: DriveIndex(0), activation: throttle),
            DriveIntent(index: DriveIndex(1), activation: driveRoll),
            DriveIntent(index: DriveIndex(2), activation: drivePitch),
            DriveIntent(index: DriveIndex(3), activation: driveYaw),
        ]

        return .driveIntents(drives, corrections: [])
    }

    private func estimateTilt(accel: SIMD3<Double>) -> (roll: Double, pitch: Double) {
        let ax = accel.x
        let ay = accel.y
        let az = accel.z

        let roll = atan2(ay, az)
        let pitch = atan2(-ax, sqrt(ay * ay + az * az))
        return (roll, pitch)
    }

    private mutating func updateEstimates(
        accelRoll: Double,
        accelPitch: Double,
        time: WorldTime
    ) -> (roll: Double, pitch: Double) {
        let currentTime = time.time
        let dt: Double
        if let lastTime {
            dt = max(0, currentTime - lastTime)
        } else {
            dt = 0
        }
        lastTime = currentTime

        estimatedRoll += gyro.x * dt
        estimatedPitch += gyro.y * dt

        if dt > 0 {
            let tau = 0.4
            let alpha = exp(-dt / tau)
            estimatedRoll = alpha * estimatedRoll + (1 - alpha) * accelRoll
            estimatedPitch = alpha * estimatedPitch + (1 - alpha) * accelPitch
        }

        return (estimatedRoll, estimatedPitch)
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private func solveThrusts(totalThrust: Double, torque: SIMD3<Double>) throws -> MotorThrusts {
        let l = armLength
        let k = yawCoefficient
        let a = torque.x / l
        let b = torque.y / l
        let c = torque.z / k
        let d = (c - b + a) / 2.0

        let f4 = (totalThrust - 2.0 * d - a - b) / 4.0
        let f1 = f4 + d
        let f2 = f4 + a
        let f3 = f4 + d + b

        guard f1.isFinite, f2.isFinite, f3.isFinite, f4.isFinite else { throw CutError.nonFiniteState }

        return try MotorThrusts(f1: f1, f2: f2, f3: f3, f4: f4)
    }
}
