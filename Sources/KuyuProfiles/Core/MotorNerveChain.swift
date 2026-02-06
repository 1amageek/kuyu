import Foundation
import KuyuCore

public struct MotorNerveChain: MotorNerveEndpoint, MotorNerveTraceProvider {
    public enum ChainError: Error, Equatable {
        case driveCountMismatch(expected: Int, actual: Int)
        case missingSignal(String)
        case missingStageInput(stage: String, signal: String)
        case invalidStageOutput(stage: String)
        case unsupportedStage(String)
        case invalidMixerParameters(String)
    }

    public var lastTrace: MotorNerveTrace? { lastTraceStorage }

    private let stages: [RobotDescriptor.MotorNerveStage]
    private let driveChannels: [String]
    private let driveClamp: RobotDescriptor.Range?
    private let actuatorSignals: [RobotDescriptor.SignalDefinition]
    private let actuatorLimits: [String: RobotDescriptor.Range]
    private let normalizedActuatorSignals: Set<String>
    private var lastTraceStorage: MotorNerveTrace?

    public init(descriptor: RobotDescriptor) throws {
        self.stages = descriptor.motorNerve.stages
        self.driveChannels = descriptor.control.driveChannels
        self.driveClamp = descriptor.control.constraints?.driveClamp
        self.actuatorSignals = descriptor.signals.actuator
        self.actuatorLimits = MotorNerveChain.buildActuatorLimits(from: descriptor.actuators)
        self.normalizedActuatorSignals = MotorNerveChain.normalizedActuatorOutputs(from: descriptor.motorNerve.stages)
        self.lastTraceStorage = nil
    }

    public mutating func update(
        input drives: [DriveIntent],
        corrections: [ReflexCorrection],
        telemetry: MotorNerveTelemetry,
        time: WorldTime
    ) throws -> [ActuatorValue] {
        _ = time

        guard drives.count == driveChannels.count else {
            throw ChainError.driveCountMismatch(expected: driveChannels.count, actual: drives.count)
        }

        var values: [String: Double] = [:]
        let adjusted = try applyCorrections(drives: drives, corrections: corrections)
        for (offset, drive) in adjusted.enumerated() {
            let signalId = driveChannels[offset]
            values[signalId] = drive.activation
        }

        for stage in stages {
            let inputs = try stage.inputs.map { id -> Double in
                guard let value = values[id] else {
                    throw ChainError.missingStageInput(stage: stage.id, signal: id)
                }
                return value
            }

            let outputs: [Double]
            switch stage.type {
            case .direct:
                outputs = inputs
            case .matrix:
                outputs = try applyMatrix(stage: stage, inputs: inputs)
            case .mixer:
                outputs = try applyMixer(stage: stage, inputs: inputs)
            case .custom:
                throw ChainError.unsupportedStage(stage.id)
            }

            guard outputs.count == stage.outputs.count else {
                throw ChainError.invalidStageOutput(stage: stage.id)
            }

            let clipped = applyClip(stage: stage, outputs: outputs)
            for (index, outputId) in stage.outputs.enumerated() {
                values[outputId] = clipped[index]
            }
        }

        var rawOutputs: [Double] = []
        rawOutputs.reserveCapacity(actuatorSignals.count)
        var saturated: [Double] = []
        saturated.reserveCapacity(actuatorSignals.count)
        var finalValues: [ActuatorValue] = []
        finalValues.reserveCapacity(actuatorSignals.count)

        for signal in actuatorSignals {
            guard let raw = values[signal.id] else {
                throw ChainError.missingSignal(signal.id)
            }
            let scaled = scaleIfNeeded(signalId: signal.id, value: raw)
            let clamped = clampToLimits(signalId: signal.id, value: scaled)
            let outputValue = telemetry.failsafeActive ? 0.0 : clamped
            rawOutputs.append(raw)
            saturated.append(clamped)
            let actuatorIndex = ActuatorIndex(UInt32(signal.index))
            finalValues.append(try ActuatorValue(index: actuatorIndex, value: outputValue))
        }

        lastTraceStorage = MotorNerveTrace(
            uRaw: rawOutputs,
            uSat: saturated,
            uRate: saturated,
            uOut: finalValues.map(\.value),
            failsafeActive: telemetry.failsafeActive
        )

        return finalValues
    }

    private func applyCorrections(
        drives: [DriveIntent],
        corrections: [ReflexCorrection]
    ) throws -> [DriveIntent] {
        guard !corrections.isEmpty else {
            return try drives.map { try clampDrive($0) }
        }

        var aggregate: [DriveIndex: ReflexAggregate] = [:]
        for correction in corrections {
            var entry = aggregate[correction.driveIndex] ?? ReflexAggregate()
            entry.clampMultiplier *= correction.clampMultiplier
            entry.damping = min(1.0, entry.damping + correction.damping)
            entry.delta += correction.delta
            aggregate[correction.driveIndex] = entry
        }

        return try drives.map { drive in
            guard let entry = aggregate[drive.index] else {
                return try clampDrive(drive)
            }
            let damped = drive.activation * (1.0 - entry.damping)
            let clamped = damped * entry.clampMultiplier
            let adjusted = clamped + entry.delta
            return try clampDrive(DriveIntent(index: drive.index, activation: adjusted, parameters: drive.parameters))
        }
    }

    private func clampDrive(_ drive: DriveIntent) throws -> DriveIntent {
        guard let clamp = driveClamp else { return drive }
        let value = min(max(drive.activation, clamp.min), clamp.max)
        return try DriveIntent(index: drive.index, activation: value, parameters: drive.parameters)
    }

    private func applyMatrix(stage: RobotDescriptor.MotorNerveStage, inputs: [Double]) throws -> [Double] {
        guard let mapping = stage.mapping, let matrix = mapping.matrix else {
            throw ChainError.invalidStageOutput(stage: stage.id)
        }
        var outputs: [Double] = []
        outputs.reserveCapacity(matrix.count)
        if let bias = mapping.bias, bias.count != matrix.count {
            throw ChainError.invalidStageOutput(stage: stage.id)
        }
        let bias = mapping.bias ?? Array(repeating: 0.0, count: matrix.count)
        for (rowIndex, row) in matrix.enumerated() {
            guard row.count == inputs.count else {
                throw ChainError.invalidStageOutput(stage: stage.id)
            }
            let base = bias[rowIndex]
            var sum = base
            for (colIndex, weight) in row.enumerated() {
                sum += weight * inputs[colIndex]
            }
            outputs.append(sum)
        }
        return outputs
    }

    private func applyMixer(stage: RobotDescriptor.MotorNerveStage, inputs: [Double]) throws -> [Double] {
        guard inputs.count == 4, stage.outputs.count == 4 else {
            throw ChainError.invalidMixerParameters(stage.id)
        }
        let throttle = inputs[0]
        let roll = inputs[1]
        let pitch = inputs[2]
        let yaw = inputs[3]
        let spin = mixerSpin(stage: stage)
        return [
            throttle - pitch + spin[0] * yaw,
            throttle + roll + spin[1] * yaw,
            throttle + pitch + spin[2] * yaw,
            throttle - roll + spin[3] * yaw
        ]
    }

    private func mixerSpin(stage: RobotDescriptor.MotorNerveStage) -> [Double] {
        if let raw = stage.parameters?["spin"] {
            let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 4, let a = Double(parts[0]), let b = Double(parts[1]),
               let c = Double(parts[2]), let d = Double(parts[3]) {
                return [a, b, c, d]
            }
        }
        return [1.0, -1.0, 1.0, -1.0]
    }

    private func applyClip(stage: RobotDescriptor.MotorNerveStage, outputs: [Double]) -> [Double] {
        guard let clip = stage.mapping?.clip else { return outputs }
        return outputs.map { min(max($0, clip.min), clip.max) }
    }

    private func scaleIfNeeded(signalId: String, value: Double) -> Double {
        guard normalizedActuatorSignals.contains(signalId),
              let limits = actuatorLimits[signalId] else {
            return value
        }
        let span = limits.max - limits.min
        return limits.min + value * span
    }

    private func clampToLimits(signalId: String, value: Double) -> Double {
        guard let limits = actuatorLimits[signalId] else { return value }
        return min(max(value, limits.min), limits.max)
    }

    private static func buildActuatorLimits(
        from actuators: [RobotDescriptor.ActuatorDefinition]
    ) -> [String: RobotDescriptor.Range] {
        var limits: [String: RobotDescriptor.Range] = [:]
        for actuator in actuators {
            let range = RobotDescriptor.Range(min: actuator.limits.min, max: actuator.limits.max)
            for channel in actuator.channels {
                limits[channel] = range
            }
        }
        return limits
    }

    private static func normalizedActuatorOutputs(
        from stages: [RobotDescriptor.MotorNerveStage]
    ) -> Set<String> {
        var normalized: Set<String> = []
        for stage in stages where stage.type == .mixer {
            for output in stage.outputs {
                normalized.insert(output)
            }
        }
        return normalized
    }

    private struct ReflexAggregate {
        var clampMultiplier: Double = 1.0
        var damping: Double = 0.0
        var delta: Double = 0.0
    }
}
