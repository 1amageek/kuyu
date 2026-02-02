import Foundation
import ManasMLX
import kuyu
import manas

struct ManasLearningDAL: ExternalDAL {
    private enum Mode {
        case off(DAL<IdentityActuatorMapper, NoActuatorLearning>)
        case affine(DAL<IdentityActuatorMapper, MLXAffineActuatorLearner>)
        case mlp(DAL<IdentityActuatorMapper, MLXMLPActuatorLearner>)
    }

    private var mode: Mode
    private var lastTime: WorldTime?

    init(
        learningMode: LearningMode,
        parameters: QuadrotorParameters,
        updatePeriod: TimeInterval
    ) throws {
        let limits = try ManasLearningDAL.buildLimits(maxThrust: parameters.maxThrust)
        let safetyFilter = SafetyFilter(limits: limits)

        switch learningMode {
        case .off:
            let dal = DAL(
                mapper: IdentityActuatorMapper(),
                learner: NoActuatorLearning(),
                safetyFilter: safetyFilter
            )
            self.mode = .off(dal)
        case .mlxAffine:
            let constraints = try LearningConstraints(
                minUpdatePeriod: updatePeriod,
                maxParameterDeltaNorm: 10.0,
                maxParameterDerivativeNorm: 1000.0
            )
            let config = try MLXAffineActuatorLearner.Configuration(
                actuatorCount: 4,
                telemetryFeatures: [.escState],
                driveRange: 0.0...parameters.maxThrust,
                telemetryRanges: [.escState: 0.0...parameters.maxThrust],
                deltaMax: parameters.maxThrust * 0.1,
                learningRate: 0.01,
                targetTelemetry: .escState,
                enabled: true
            )
            let learner = MLXAffineActuatorLearner(configuration: config)
            let dal = DAL(
                mapper: IdentityActuatorMapper(),
                learner: learner,
                safetyFilter: safetyFilter,
                learningConstraints: constraints
            )
            self.mode = .affine(dal)
        case .mlxMLP:
            let constraints = try LearningConstraints(
                minUpdatePeriod: updatePeriod,
                maxParameterDeltaNorm: 10.0,
                maxParameterDerivativeNorm: 1000.0
            )
            let config = try MLXMLPActuatorLearner.Configuration(
                actuatorCount: 4,
                telemetryFeatures: [.escState],
                driveRange: 0.0...parameters.maxThrust,
                telemetryRanges: [.escState: 0.0...parameters.maxThrust],
                deltaMax: parameters.maxThrust * 0.1,
                learningRate: 0.01,
                hiddenSize: 8,
                targetTelemetry: .escState,
                enabled: true
            )
            let learner = MLXMLPActuatorLearner(configuration: config)
            let dal = DAL(
                mapper: IdentityActuatorMapper(),
                learner: learner,
                safetyFilter: safetyFilter,
                learningConstraints: constraints
            )
            self.mode = .mlp(dal)
        }
    }

    mutating func update(
        drives: [kuyu.DriveIntent],
        telemetry: ExternalDALTelemetry,
        time: WorldTime
    ) throws -> [kuyu.ActuatorCommand] {
        let deltaTime = deltaTimeSinceLast(time: time)
        let dalTelemetry = try manasTelemetry(from: telemetry)
        let mappedDrives = try manasDriveIntents(from: drives)

        switch mode {
        case .off(var dal):
            let commands = try dal.update(
                drives: mappedDrives,
                telemetry: dalTelemetry,
                deltaTime: deltaTime
            )
            mode = .off(dal)
            return try kuyuCommands(from: commands)
        case .affine(var dal):
            let commands = try dal.update(
                drives: mappedDrives,
                telemetry: dalTelemetry,
                deltaTime: deltaTime
            )
            mode = .affine(dal)
            return try kuyuCommands(from: commands)
        case .mlp(var dal):
            let commands = try dal.update(
                drives: mappedDrives,
                telemetry: dalTelemetry,
                deltaTime: deltaTime
            )
            mode = .mlp(dal)
            return try kuyuCommands(from: commands)
        }
    }

    private mutating func deltaTimeSinceLast(time: WorldTime) -> TimeInterval {
        let delta: TimeInterval
        if let lastTime {
            delta = max(0, time.time - lastTime.time)
        } else {
            delta = max(0, time.time)
        }
        lastTime = time
        return delta
    }

    private func manasDriveIntents(from drives: [kuyu.DriveIntent]) throws -> [manas.DriveIntent] {
        try drives.map { drive in
            let index = manas.DriveIndex(drive.index.rawValue)
            return try manas.DriveIntent(index: index, activation: drive.activation)
        }
    }

    private func manasTelemetry(from telemetry: ExternalDALTelemetry) throws -> manas.DALTelemetry {
        let thrusts = telemetry.motorThrusts
        let values = [thrusts.f1, thrusts.f2, thrusts.f3, thrusts.f4]
        let motors = try values.enumerated().map { offset, value in
            try manas.MotorTelemetry(
                index: manas.ActuatorIndex(UInt32(offset)),
                rpm: nil,
                current: nil,
                voltage: nil,
                temperature: nil,
                escState: value
            )
        }
        return manas.DALTelemetry(motors: motors)
    }

    private func kuyuCommands(from commands: [manas.ActuatorCommand]) throws -> [kuyu.ActuatorCommand] {
        try commands.map { command in
            let index = kuyu.ActuatorIndex(command.index.rawValue)
            return try kuyu.ActuatorCommand(index: index, value: command.value)
        }
    }

    private static func buildLimits(maxThrust: Double) throws -> manas.ActuatorLimits {
        let limit = try manas.ActuatorLimit(range: 0.0...maxThrust, maxRate: nil)
        var limits: [manas.ActuatorIndex: manas.ActuatorLimit] = [:]
        for idx in 0..<4 {
            limits[manas.ActuatorIndex(UInt32(idx))] = limit
        }
        return manas.ActuatorLimits(limits: limits)
    }
}
