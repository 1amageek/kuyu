import KuyuCore

public struct KuyAtt1Suite: ReferenceQuadrotorScenarioSuite {
    public init() {}

    public func scenarios() throws -> [ReferenceQuadrotorScenarioDefinition] {
        let seeds: [UInt64] = [1001, 1002, 1003]
        let timeStep = try TimeStep(delta: 0.001)
        let duration: Double = 20.0
        let envelope = try SafetyEnvelope(
            omegaSafeMax: 20.0,
            tiltSafeMaxDegrees: 60.0,
            sustainedViolationSeconds: 0.200,
            groundZ: 0.0,
            fallDurationSeconds: 0.5,
            fallVelocityThreshold: 0.0
        )

        let definitions: [ReferenceQuadrotorScenarioDefinition] = try buildDefinitions(
            seeds: seeds,
            timeStep: timeStep,
            duration: duration,
            envelope: envelope
        )
        return definitions
    }

    private func buildDefinitions(
        seeds: [UInt64],
        timeStep: TimeStep,
        duration: Double,
        envelope: SafetyEnvelope
    ) throws -> [ReferenceQuadrotorScenarioDefinition] {
        var results: [ReferenceQuadrotorScenarioDefinition] = []
        results.reserveCapacity(seeds.count * 5)
        let initialPosition = Axis3(x: 0, y: 0, z: 2.0)

        for seed in seeds {
            let seedValue = ScenarioSeed(seed)

            let scn1 = try ScenarioConfig(
                id: ScenarioID("KUY-ATT-1/SCN-1"),
                seed: seedValue,
                duration: duration,
                timeStep: timeStep
            )
            results.append(ReferenceQuadrotorScenarioDefinition(
                config: scn1,
                kind: .hoverStart,
                initialPosition: initialPosition,
                initialAttitude: EulerAngles.degrees(roll: 10, pitch: 0, yaw: 0),
                initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
                safetyEnvelope: envelope,
                torqueEvents: [],
                actuatorDegradation: nil,
                gyroDriftScale: 1.0,
                swapEvents: [],
                hfEvents: []
            ))

            let scn2 = try ScenarioConfig(
                id: ScenarioID("KUY-ATT-1/SCN-2"),
                seed: seedValue,
                duration: duration,
                timeStep: timeStep
            )
            let impulse = try TorqueDisturbanceEvent(
                startTime: 5.0,
                duration: 0.020,
                torqueBody: Axis3(x: 0.20, y: 0, z: 0)
            )
            results.append(ReferenceQuadrotorScenarioDefinition(
                config: scn2,
                kind: .impulseTorqueShock,
                initialPosition: initialPosition,
                initialAttitude: EulerAngles(roll: 0, pitch: 0, yaw: 0),
                initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
                safetyEnvelope: envelope,
                torqueEvents: [impulse],
                actuatorDegradation: nil,
                gyroDriftScale: 1.0,
                swapEvents: [],
                hfEvents: []
            ))

            let scn3 = try ScenarioConfig(
                id: ScenarioID("KUY-ATT-1/SCN-3"),
                seed: seedValue,
                duration: duration,
                timeStep: timeStep
            )
            let sustained = try TorqueDisturbanceEvent(
                startTime: 5.0,
                duration: 10.0,
                torqueBody: Axis3(x: 0.05, y: 0, z: 0)
            )
            results.append(ReferenceQuadrotorScenarioDefinition(
                config: scn3,
                kind: .sustainedWindTorque,
                initialPosition: initialPosition,
                initialAttitude: EulerAngles(roll: 0, pitch: 0, yaw: 0),
                initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
                safetyEnvelope: envelope,
                torqueEvents: [sustained],
                actuatorDegradation: nil,
                gyroDriftScale: 1.0,
                swapEvents: [],
                hfEvents: []
            ))

            let scn4 = try ScenarioConfig(
                id: ScenarioID("KUY-ATT-1/SCN-4"),
                seed: seedValue,
                duration: duration,
                timeStep: timeStep
            )
            results.append(ReferenceQuadrotorScenarioDefinition(
                config: scn4,
                kind: .sensorDriftStress,
                initialPosition: initialPosition,
                initialAttitude: EulerAngles(roll: 0, pitch: 0, yaw: 0),
                initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
                safetyEnvelope: envelope,
                torqueEvents: [],
                actuatorDegradation: nil,
                gyroDriftScale: 5.0,
                swapEvents: [],
                hfEvents: []
            ))

            let scn5 = try ScenarioConfig(
                id: ScenarioID("KUY-ATT-1/SCN-5"),
                seed: seedValue,
                duration: duration,
                timeStep: timeStep
            )
            let degradation = try ActuatorDegradation(
                startTime: 5.0,
                motorIndex: 0,
                maxThrustScale: 0.70
            )
            results.append(ReferenceQuadrotorScenarioDefinition(
                config: scn5,
                kind: .actuatorDegradation,
                initialPosition: initialPosition,
                initialAttitude: EulerAngles(roll: 0, pitch: 0, yaw: 0),
                initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
                safetyEnvelope: envelope,
                torqueEvents: [],
                actuatorDegradation: degradation,
                gyroDriftScale: 1.0,
                swapEvents: [],
                hfEvents: []
            ))
        }

        return results
    }
}
