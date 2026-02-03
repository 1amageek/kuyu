public struct ScenarioManifestBuilder {
    public init() {}

    public func build(from definitions: [ScenarioDefinition]) -> [ScenarioManifest] {
        definitions.map { definition in
            ScenarioManifest(
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
