import KuyuCore

public struct ReferenceQuadrotorScenarioManifestBuilder {
    public init() {}

    public func build(from definitions: [ReferenceQuadrotorScenarioDefinition]) -> [ReferenceQuadrotorScenarioManifest] {
        definitions.map { definition in
            ReferenceQuadrotorScenarioManifest(
                scenarioId: definition.config.id,
                seed: definition.config.seed,
                kind: definition.kind,
                duration: definition.config.duration,
                timeStep: definition.config.timeStep,
                torqueEvents: definition.torqueEvents,
                actuatorDegradation: definition.actuatorDegradation,
                gyroDriftScale: definition.gyroDriftScale,
                swapEvents: definition.swapEvents,
                hfEvents: definition.hfEvents
            )
        }
    }
}
