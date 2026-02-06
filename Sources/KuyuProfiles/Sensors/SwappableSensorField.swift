import Foundation
import KuyuCore

public struct SwappableSensorField: SensorField {
    public var base: IMU6SensorField
    public let swapEvents: [SwapEvent]
    public let hfEvents: [HFStressEvent]
    public let baseNoise: IMU6NoiseConfig
    public let seed: UInt64

    private var delayBuffer: SampleDelayBuffer
    private var currentDelay: UInt64
    private var noiseModels: [GaussianNoise]

    public init(
        base: IMU6SensorField,
        swapEvents: [SwapEvent],
        hfEvents: [HFStressEvent],
        baseNoise: IMU6NoiseConfig,
        seed: UInt64
    ) {
        self.base = base
        self.swapEvents = swapEvents
        self.hfEvents = hfEvents
        self.baseNoise = baseNoise
        self.seed = seed
        self.currentDelay = 0
        self.delayBuffer = SampleDelayBuffer(delaySteps: 0)
        self.noiseModels = (0..<6).map { GaussianNoise(stdDev: 1.0, seed: seed &+ UInt64($0 + 1)) }
    }

    public mutating func sample(time: WorldTime) throws -> [ChannelSample] {
        let baseSamples = try base.sample(time: time)
        if baseSamples.isEmpty {
            return []
        }

        let modifiers = modifiersForTime(time)
        if modifiers.delaySteps != currentDelay {
            currentDelay = modifiers.delaySteps
            delayBuffer = SampleDelayBuffer(delaySteps: currentDelay)
        }

        var updated: [ChannelSample] = []
        updated.reserveCapacity(baseSamples.count)

        for sample in baseSamples {
            let idx = Int(sample.channelIndex)
            guard idx >= 0, idx < 6 else { continue }

            let channelMods = modifiers.channel[idx]
            if channelMods.dropoutProbability > 0 {
                let rand = deterministicUniform(time: time.stepIndex, channelIndex: sample.channelIndex)
                if rand < channelMods.dropoutProbability {
                    continue
                }
            }

            let extraStd = extraNoiseStdDev(
                channelIndex: idx,
                noiseScale: channelMods.noiseScale
            )
            var value = sample.value
            value = value * channelMods.gainScale + channelMods.biasShift
            if extraStd > 0 {
                noiseModels[idx].stdDev = extraStd
                value += noiseModels[idx].sample()
            }

            updated.append(try ChannelSample(channelIndex: sample.channelIndex, value: value, timestamp: sample.timestamp))
        }

        return delayBuffer.push(updated)
    }

    private func extraNoiseStdDev(channelIndex: Int, noiseScale: Double) -> Double {
        let scale = max(0.0, noiseScale - 1.0)
        let baseStd: Double
        if channelIndex < 3 {
            baseStd = baseNoise.gyroNoiseStdDev
        } else {
            baseStd = baseNoise.accelNoiseStdDev
        }
        return baseStd * scale
    }

    private func deterministicUniform(time: UInt64, channelIndex: UInt32) -> Double {
        var rng = SplitMix64(seed: seed &+ time &+ UInt64(channelIndex))
        return rng.nextDouble()
    }

    private func modifiersForTime(_ time: WorldTime) -> Modifiers {
        var modifiers = Modifiers()
        let now = time.time

        for event in swapEvents {
            guard case .sensor(let sensor) = event else { continue }
            guard now >= sensor.startTime && now <= sensor.startTime + sensor.duration else { continue }
            for channel in sensor.targetChannels {
                let idx = Int(channel)
                guard idx >= 0, idx < modifiers.channel.count else { continue }
                modifiers.channel[idx].gainScale *= sensor.gainScale
                modifiers.channel[idx].biasShift += sensor.biasShift
                modifiers.channel[idx].noiseScale *= sensor.noiseScale
                modifiers.channel[idx].dropoutProbability = combineDropout(
                    modifiers.channel[idx].dropoutProbability,
                    sensor.dropoutProbability
                )
            }
            modifiers.delaySteps = addDelay(modifiers.delaySteps, sensor.delayShiftSteps)
        }

        for event in hfEvents {
            guard now >= event.startTime && now <= event.startTime + event.duration else { continue }
            switch event.kind {
            case .sensorGlitch:
                for idx in 0..<modifiers.channel.count {
                    let sign = deterministicUniform(time: time.stepIndex &+ UInt64(idx), channelIndex: UInt32(idx)) < 0.5 ? -1.0 : 1.0
                    modifiers.channel[idx].biasShift += sign * event.magnitude
                }
            case .latencySpike:
                let extra = max(1, Int(event.magnitude))
                modifiers.delaySteps = addDelay(modifiers.delaySteps, extra)
            default:
                break
            }
        }

        return modifiers
    }

    private func combineDropout(_ a: Double, _ b: Double) -> Double {
        let clampedA = min(max(a, 0.0), 1.0)
        let clampedB = min(max(b, 0.0), 1.0)
        return 1.0 - ((1.0 - clampedA) * (1.0 - clampedB))
    }

    private func addDelay(_ base: UInt64, _ shift: Int) -> UInt64 {
        if shift == 0 { return base }
        let next = Int(base) + shift
        return UInt64(max(0, next))
    }

    private struct ChannelModifiers {
        var gainScale: Double = 1.0
        var biasShift: Double = 0.0
        var noiseScale: Double = 1.0
        var dropoutProbability: Double = 0.0
    }

    private struct Modifiers {
        var channel: [ChannelModifiers] = Array(repeating: ChannelModifiers(), count: 6)
        var delaySteps: UInt64 = 0
    }
}
