import KuyuCore
import KuyuPhysics
import KuyuScenarios

public struct KuyuSingleLiftTrainingSuite {
    public init() {}

    public func scenarios() throws -> [ReferenceQuadrotorScenarioDefinition] {
        let base = try KuySingleLiftSuite().scenarios()
        guard let template = base.first, let lift = template.liftEnvelope else {
            return base
        }

        let altitudeOffsets: [Double] = [
            -0.25, -0.15, -0.09, -0.06, -0.03,
            0.0, 0.0, 0.0,
            0.03, 0.06, 0.09, 0.15, 0.25
        ]
        return try altitudeOffsets.enumerated().map { index, offset in
            let scenarioIndex = index + 1
            let config = try ScenarioConfig(
                id: ScenarioID("KUY-SLIFT-TRAIN/SCN-\(scenarioIndex)"),
                seed: ScenarioSeed(UInt64(2_000 + scenarioIndex)),
                duration: template.config.duration,
                timeStep: template.config.timeStep
            )
            return ReferenceQuadrotorScenarioDefinition(
                config: config,
                kind: template.kind,
                initialPosition: Axis3(x: 0, y: 0, z: lift.targetZ + offset),
                initialAttitude: template.initialAttitude,
                initialAngularVelocity: template.initialAngularVelocity,
                safetyEnvelope: template.safetyEnvelope,
                liftEnvelope: template.liftEnvelope,
                torqueEvents: template.torqueEvents,
                actuatorDegradation: template.actuatorDegradation,
                gyroDriftScale: template.gyroDriftScale,
                swapEvents: template.swapEvents,
                hfEvents: template.hfEvents
            )
        }
    }
}
