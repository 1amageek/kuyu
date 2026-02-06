import ManasCore
import ManasMLXModels
import ManasMLXRuntime
import KuyuCore

public struct ManasMLXCut: CutInterface {
    public enum CutError: Error, Equatable {
        case trunkSizeMismatch(expected: Int, actual: Int)
        case reflexInputMismatch(expected: Int, actual: Int)
    }

    private var bundle: Imu6NerveBundle
    private var gate: any Gating
    private var trunks: BasicTrunksBuilder
    private var core: ManasMLXCoreController
    private var reflex: ManasMLXReflexController

    public init(
        coreModel: ManasMLXCore,
        reflexModel: ManasMLXReflex,
        useQualityGating: Bool
    ) throws {
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
        core = ManasMLXCoreController(model: coreModel)
        reflex = ManasMLXReflexController(model: reflexModel)
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

        let manasDrives = try core.update(trunks: trunkBundle, time: time.time)
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
}
