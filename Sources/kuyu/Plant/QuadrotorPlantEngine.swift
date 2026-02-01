import simd

public struct QuadrotorPlantEngine: PlantEngine {
    public enum PlantError: Error, Equatable {
        case nonFiniteState
    }

    public var parameters: QuadrotorParameters
    public var mixer: QuadrotorMixer
    public var store: WorldStore
    public let timeStep: TimeStep

    public init(
        parameters: QuadrotorParameters,
        mixer: QuadrotorMixer,
        store: WorldStore,
        timeStep: TimeStep
    ) {
        self.parameters = parameters
        self.mixer = mixer
        self.store = store
        self.timeStep = timeStep
    }

    public mutating func integrate(time: WorldTime) throws {
        let mix = mixer.mix(thrusts: store.motorThrusts)
        let input = QuadrotorInput(
            bodyForce: mix.forceBody,
            bodyTorque: mix.torqueBody + store.disturbances.torqueBody,
            worldForce: store.disturbances.forceWorld
        )

        let next = QuadrotorDynamics.integrateRK4(
            state: store.state,
            input: input,
            parameters: parameters,
            delta: timeStep.delta
        )

        guard next.position.x.isFinite,
              next.position.y.isFinite,
              next.position.z.isFinite,
              next.velocity.x.isFinite,
              next.velocity.y.isFinite,
              next.velocity.z.isFinite,
              next.angularVelocity.x.isFinite,
              next.angularVelocity.y.isFinite,
              next.angularVelocity.z.isFinite,
              next.orientation.vector.x.isFinite,
              next.orientation.vector.y.isFinite,
              next.orientation.vector.z.isFinite,
              next.orientation.vector.w.isFinite else {
            throw PlantError.nonFiniteState
        }

        store.state = next
    }
}
