import ManasCore
import ManasMLXModels
import ManasMLXRuntime
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public struct ManasMLXCut: CutInterface {
    public enum CutError: Error, Equatable {
        case trunkSizeMismatch(expected: Int, actual: Int)
        case reflexInputMismatch(expected: Int, actual: Int)
        case conflictingDescendingInputs
        case nonFiniteDescending
    }

    private var bundle: Imu6NerveBundle
    private var gate: any Gating
    private var trunks: BasicTrunksBuilder
    private var core: MLXDescendingCoreController
    private var reflex: ManasMLXReflexController
    private let descendingTargetSize: Int
    private let fixedDescendingVector: [Double]?
    private let descendingProgram: DescendingIntentProgram?

    public init(
        coreModel: ManasMLXCore,
        reflexModel: ManasMLXReflex,
        useQualityGating: Bool,
        descendingVector: [Double]? = nil,
        descendingProgram: DescendingIntentProgram? = nil
    ) throws {
        if descendingVector != nil, descendingProgram != nil {
            throw CutError.conflictingDescendingInputs
        }
        let bundleConfig = Imu6NerveBundle.Configuration(
            gyroRange: -20...20,
            accelRange: -20...20
        )
        bundle = Imu6NerveBundle(configuration: bundleConfig)
        gate = useQualityGating
            ? QualityGating(configuration: .init(minGate: 0.2, maxGate: 1.0))
            : IdentityGating()
        trunks = BasicTrunksBuilder()

        let sizing = try Self.computeSizing(bundle: &bundle, gate: &gate, trunks: &trunks)
        if coreModel.config.inputSize != sizing.trunkSize {
            throw CutError.trunkSizeMismatch(expected: coreModel.config.inputSize, actual: sizing.trunkSize)
        }
        if reflexModel.config.inputSize != sizing.fastTapCount {
            throw CutError.reflexInputMismatch(expected: reflexModel.config.inputSize, actual: sizing.fastTapCount)
        }
        core = MLXDescendingCoreController(model: coreModel)
        reflex = ManasMLXReflexController(model: reflexModel)
        descendingTargetSize = coreModel.config.descendingSize
        fixedDescendingVector = descendingVector
        self.descendingProgram = descendingProgram
    }

    public mutating func update(samples: [ChannelSample], time: WorldTime) throws -> CutOutput {
        let signalSamples = try samples.map { sample in
            try SignalSample(
                channelIndex: sample.channelIndex,
                value: sample.value,
                timestamp: sample.timestamp
            )
        }

        let bundled = try bundle.process(samples: signalSamples, time: time.time)
        let gated = try gate.apply(bundle: bundled, time: time.time)
        let trunkBundle = try trunks.build(from: gated, time: time.time)
        let goals = try buildGoals(at: time.time)

        let manasDrives = try core.update(trunks: trunkBundle, goals: goals, time: time.time)
        let manasCorrections = try reflex.update(bundle: bundled, trunks: trunkBundle, time: time.time)

        let drives = try manasDrives.map { drive in
            try KuyuCore.DriveIntent(
                index: KuyuCore.DriveIndex(drive.index.rawValue),
                activation: drive.activation,
                parameters: drive.parameters
            )
        }
        let corrections = try manasCorrections.map { correction in
            try KuyuCore.ReflexCorrection(
                driveIndex: KuyuCore.DriveIndex(correction.driveIndex.rawValue),
                clampMultiplier: correction.clampMultiplier,
                damping: correction.damping,
                delta: correction.delta
            )
        }

        return .driveIntents(drives, corrections: corrections)
    }

    public static func computeSizing(
        bundle: inout Imu6NerveBundle,
        gate: inout any Gating,
        trunks: inout BasicTrunksBuilder
    ) throws -> (trunkSize: Int, fastTapCount: Int, driveCount: Int) {
        var samples: [SignalSample] = []
        samples.reserveCapacity(6)
        for index in 0..<6 {
            let sample = try SignalSample(channelIndex: UInt32(index), value: 0.0, timestamp: 0.0)
            samples.append(sample)
        }
        let bundled = try bundle.process(samples: samples, time: 0.0)
        let gated = try gate.apply(bundle: bundled, time: 0.0)
        let trunkBundle = try trunks.build(from: gated, time: 0.0)
        let trunkVector = concatTrunks(trunkBundle)
        return (trunkVector.count, bundled.fastTaps.count, 4)
    }

    private static func concatTrunks(_ bundle: TrunkBundle) -> [Float] {
        bundle.energy.map(Float.init)
        + bundle.phase.map(Float.init)
        + bundle.quality.map(Float.init)
        + bundle.spike.map(Float.init)
    }

    private static func normalizeDescending(
        _ descendingVector: [Double]?,
        targetSize: Int
    ) throws -> [Double] {
        guard targetSize > 0 else { return [] }
        guard let descendingVector else { return [] }
        guard descendingVector.allSatisfy({ $0.isFinite }) else {
            throw CutError.nonFiniteDescending
        }

        if descendingVector.count >= targetSize {
            return Array(descendingVector.prefix(targetSize))
        }
        return descendingVector + [Double](repeating: 0, count: targetSize - descendingVector.count)
    }

    private func buildGoals(at time: Double) throws -> [ControlGoal] {
        let rawDescending: [Double]?
        if let descendingProgram {
            rawDescending = descendingProgram.vector(at: time)
        } else {
            rawDescending = fixedDescendingVector
        }

        let descending = try Self.normalizeDescending(rawDescending, targetSize: descendingTargetSize)
        guard !descending.isEmpty else {
            return []
        }
        return [try ControlGoal(kind: .referenceSignal, vector: descending)]
    }
}
