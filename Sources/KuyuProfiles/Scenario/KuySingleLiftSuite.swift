import KuyuCore

public struct KuySingleLiftSuite: ReferenceQuadrotorScenarioSuite {
    public init() {}

    public func scenarios() throws -> [ReferenceQuadrotorScenarioDefinition] {
        let seeds: [UInt64] = [1001, 1002, 1003]
        let timeStep = try TimeStep(delta: 0.002)
        let duration: Double = 8.0
        let envelope = try SafetyEnvelope(
            omegaSafeMax: 1000.0,
            tiltSafeMaxDegrees: 180.0,
            sustainedViolationSeconds: 999.0,
            groundZ: 0.0,
            fallDurationSeconds: 0.5,
            fallVelocityThreshold: 0.5
        )
        let liftEnvelope = LiftEnvelope(
            targetZ: 0.5,
            tolerance: 0.08,
            maxVelocity: 0.3,
            warmupTime: 0.6,
            requiredHoldTime: 2.5
        )

        var definitions: [ReferenceQuadrotorScenarioDefinition] = []
        definitions.reserveCapacity(seeds.count)
        let initialPosition = Axis3(x: 0, y: 0, z: 0.0)

        for seed in seeds {
            let config = try ScenarioConfig(
                id: ScenarioID("KUY-SLIFT-1/SCN-1"),
                seed: ScenarioSeed(seed),
                duration: duration,
                timeStep: timeStep
            )
            definitions.append(ReferenceQuadrotorScenarioDefinition(
                config: config,
                kind: .singleLiftHover,
                initialPosition: initialPosition,
                initialAttitude: EulerAngles(roll: 0, pitch: 0, yaw: 0),
                initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
                safetyEnvelope: envelope,
                liftEnvelope: liftEnvelope,
                torqueEvents: [],
                actuatorDegradation: nil,
                gyroDriftScale: 1.0,
                swapEvents: [],
                hfEvents: []
            ))
        }

        return definitions
    }
}
