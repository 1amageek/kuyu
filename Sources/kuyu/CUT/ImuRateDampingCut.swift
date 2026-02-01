import simd

public struct ImuRateDampingCut: CutInterface {
    public enum CutError: Error, Equatable {
        case invalidHoverThrust
        case nonFiniteState
        case invalidMixerParameters
    }

    public var hoverThrust: Double
    public var kp: Double
    public var kd: Double
    public var yawDamping: Double
    public var armLength: Double
    public var yawCoefficient: Double

    private var gyro: SIMD3<Double>
    private var accel: SIMD3<Double>

    public init(
        hoverThrust: Double,
        kp: Double,
        kd: Double,
        yawDamping: Double,
        armLength: Double,
        yawCoefficient: Double
    ) throws {
        guard hoverThrust.isFinite else { throw CutError.invalidHoverThrust }
        guard armLength > 0, yawCoefficient > 0 else { throw CutError.invalidMixerParameters }

        self.hoverThrust = hoverThrust
        self.kp = kp
        self.kd = kd
        self.yawDamping = yawDamping
        self.armLength = armLength
        self.yawCoefficient = yawCoefficient
        self.gyro = SIMD3<Double>(repeating: 0)
        self.accel = SIMD3<Double>(0, 0, 1)
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
        let tauX = -kp * roll - kd * gyro.x
        let tauY = -kp * pitch - kd * gyro.y
        let tauZ = -yawDamping * gyro.z

        guard tauX.isFinite, tauY.isFinite, tauZ.isFinite else { throw CutError.nonFiniteState }

        let thrusts = try solveThrusts(
            totalThrust: hoverThrust * 4.0,
            torque: SIMD3<Double>(tauX, tauY, tauZ)
        )

        let commands = try [
            ActuatorCommand(index: ActuatorIndex(0), value: thrusts.f1),
            ActuatorCommand(index: ActuatorIndex(1), value: thrusts.f2),
            ActuatorCommand(index: ActuatorIndex(2), value: thrusts.f3),
            ActuatorCommand(index: ActuatorIndex(3), value: thrusts.f4)
        ]

        return .actuatorCommands(commands)
    }

    private func estimateTilt(accel: SIMD3<Double>) -> (roll: Double, pitch: Double) {
        let ax = accel.x
        let ay = accel.y
        let az = accel.z

        let roll = atan2(ay, az)
        let pitch = atan2(-ax, sqrt(ay * ay + az * az))
        return (roll, pitch)
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
