import Foundation
import KuyuCore

/// Generates scenarios by sampling from a parametric space, enabling
/// automated domain randomization and curriculum learning.
///
/// Inspired by Micro-World's MineDojo data collection pipeline,
/// this replaces manual scenario definition with automated generation.
public struct ParametricScenarioGenerator {
    public enum GeneratorError: Error, Equatable {
        case invalidCount
    }

    /// Defines the ranges for each scenario parameter.
    public struct ParameterSpace: Sendable, Codable, Equatable {
        public let tiltRange: ClosedRange<Double>
        public let torqueMagnitudeRange: ClosedRange<Double>
        public let torqueDurationRange: ClosedRange<Double>
        public let degradationScaleRange: ClosedRange<Double>
        public let gyroDriftRange: ClosedRange<Double>
        public let durationRange: ClosedRange<Double>

        public init(
            tiltRange: ClosedRange<Double> = 0...30,
            torqueMagnitudeRange: ClosedRange<Double> = 0...0.5,
            torqueDurationRange: ClosedRange<Double> = 0.01...10.0,
            degradationScaleRange: ClosedRange<Double> = 0.5...1.0,
            gyroDriftRange: ClosedRange<Double> = 1.0...10.0,
            durationRange: ClosedRange<Double> = 10.0...30.0
        ) {
            self.tiltRange = tiltRange
            self.torqueMagnitudeRange = torqueMagnitudeRange
            self.torqueDurationRange = torqueDurationRange
            self.degradationScaleRange = degradationScaleRange
            self.gyroDriftRange = gyroDriftRange
            self.durationRange = durationRange
        }
    }

    public let parameterSpace: ParameterSpace

    public init(parameterSpace: ParameterSpace = ParameterSpace()) {
        self.parameterSpace = parameterSpace
    }

    /// Generate `count` random scenarios from the parameter space.
    public func generate(count: Int, baseSeed: UInt64) throws -> [ReferenceQuadrotorScenarioDefinition] {
        guard count > 0 else { throw GeneratorError.invalidCount }

        var rng = SplitMix64(seed: baseSeed)
        return try (0..<count).map { index in
            try generateOne(index: index, baseSeed: baseSeed, rng: &rng)
        }
    }

    /// Generate scenarios organized by difficulty level for curriculum learning.
    ///
    /// Level 0 is easiest (narrow parameter ranges near baseline),
    /// higher levels progressively expand toward the full parameter space.
    public func generateCurriculum(
        levels: Int,
        scenariosPerLevel: Int,
        baseSeed: UInt64
    ) throws -> [[ReferenceQuadrotorScenarioDefinition]] {
        guard levels > 0, scenariosPerLevel > 0 else { throw GeneratorError.invalidCount }

        return try (0..<levels).map { level in
            let fraction = Double(level + 1) / Double(levels)
            let levelSpace = scaledParameterSpace(fraction: fraction)
            let levelGenerator = ParametricScenarioGenerator(parameterSpace: levelSpace)
            let levelSeed = baseSeed &+ UInt64(level) &* 7919
            return try levelGenerator.generate(count: scenariosPerLevel, baseSeed: levelSeed)
        }
    }

    // MARK: - Private

    private func generateOne(
        index: Int,
        baseSeed: UInt64,
        rng: inout SplitMix64
    ) throws -> ReferenceQuadrotorScenarioDefinition {
        let seed = baseSeed &+ UInt64(index) &* 31
        let duration = sample(range: parameterSpace.durationRange, rng: &rng)
        let tiltDeg = sample(range: parameterSpace.tiltRange, rng: &rng)
        let tiltRad = tiltDeg * Double.pi / 180.0
        let torqueMag = sample(range: parameterSpace.torqueMagnitudeRange, rng: &rng)
        let torqueDur = sample(range: parameterSpace.torqueDurationRange, rng: &rng)
        let degradationScale = sample(range: parameterSpace.degradationScaleRange, rng: &rng)
        let gyroDrift = sample(range: parameterSpace.gyroDriftRange, rng: &rng)

        let scenarioId = try ScenarioID("GEN-\(baseSeed)/SCN-\(index)")
        let config = try ScenarioConfig(
            id: scenarioId,
            seed: ScenarioSeed(seed),
            duration: duration,
            timeStep: TimeStep(delta: 0.001)
        )

        // Deterministic scenario kind selection based on index
        let kinds: [ReferenceQuadrotorScenarioKind] = [
            .hoverStart, .impulseTorqueShock, .sustainedWindTorque,
            .sensorDriftStress, .actuatorDegradation
        ]
        let kind = kinds[index % kinds.count]

        let torqueEvents: [TorqueDisturbanceEvent]
        if kind == .impulseTorqueShock || kind == .sustainedWindTorque {
            torqueEvents = [
                try TorqueDisturbanceEvent(
                    startTime: duration * 0.25,
                    duration: torqueDur,
                    torqueBody: Axis3(x: torqueMag, y: 0, z: 0)
                )
            ]
        } else {
            torqueEvents = []
        }

        let actuatorDegradation: ActuatorDegradation?
        if kind == .actuatorDegradation {
            actuatorDegradation = try ActuatorDegradation(
                startTime: duration * 0.25,
                motorIndex: 0,
                maxThrustScale: degradationScale
            )
        } else {
            actuatorDegradation = nil
        }

        return ReferenceQuadrotorScenarioDefinition(
            config: config,
            kind: kind,
            initialPosition: Axis3(x: 0, y: 0, z: 2),
            initialAttitude: EulerAngles(roll: tiltRad, pitch: 0, yaw: 0),
            initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
            safetyEnvelope: try SafetyEnvelope(
                omegaSafeMax: 20.0,
                tiltSafeMaxDegrees: 60.0,
                sustainedViolationSeconds: 0.2,
                groundZ: 0.0,
                fallDurationSeconds: 0.5,
                fallVelocityThreshold: 0.0
            ),
            torqueEvents: torqueEvents,
            actuatorDegradation: actuatorDegradation,
            gyroDriftScale: kind == .sensorDriftStress ? gyroDrift : 1.0,
            swapEvents: [],
            hfEvents: []
        )
    }

    private func scaledParameterSpace(fraction: Double) -> ParameterSpace {
        ParameterSpace(
            tiltRange: scale(parameterSpace.tiltRange, fraction: fraction),
            torqueMagnitudeRange: scale(parameterSpace.torqueMagnitudeRange, fraction: fraction),
            torqueDurationRange: scale(parameterSpace.torqueDurationRange, fraction: fraction),
            degradationScaleRange: scaleInverse(parameterSpace.degradationScaleRange, fraction: fraction),
            gyroDriftRange: scale(parameterSpace.gyroDriftRange, fraction: fraction),
            durationRange: parameterSpace.durationRange
        )
    }

    private func scale(_ range: ClosedRange<Double>, fraction: Double) -> ClosedRange<Double> {
        let width = range.upperBound - range.lowerBound
        let scaledUpper = range.lowerBound + width * fraction
        return range.lowerBound...max(range.lowerBound, scaledUpper)
    }

    private func scaleInverse(_ range: ClosedRange<Double>, fraction: Double) -> ClosedRange<Double> {
        let width = range.upperBound - range.lowerBound
        let scaledLower = range.upperBound - width * fraction
        return min(range.upperBound, scaledLower)...range.upperBound
    }

    private func sample(range: ClosedRange<Double>, rng: inout SplitMix64) -> Double {
        let t = Double(rng.next() & 0xFFFFFFFF) / Double(UInt32.max)
        return range.lowerBound + t * (range.upperBound - range.lowerBound)
    }
}
