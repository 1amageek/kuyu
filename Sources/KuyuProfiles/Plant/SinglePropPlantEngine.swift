import simd
import KuyuCore

public struct SinglePropPlantEngine: PlantEngine {
    public enum PlantError: Error, Equatable {
        case nonFiniteState
    }

    public var parameters: ReferenceQuadrotorParameters
    public var store: ReferenceQuadrotorWorldStore
    public let timeStep: TimeStep
    public let environment: WorldEnvironment

    public init(
        parameters: ReferenceQuadrotorParameters,
        store: ReferenceQuadrotorWorldStore,
        timeStep: TimeStep,
        environment: WorldEnvironment = .standard
    ) {
        self.parameters = parameters
        self.store = store
        self.timeStep = timeStep
        self.environment = environment
    }

    public mutating func integrate(time: WorldTime) throws {
        _ = time
        let gravity = environment.effectiveGravity(defaultGravity: parameters.gravity)
        let thrust = store.motorThrusts.f1
        let forceZ = thrust + store.disturbances.forceWorld.z
        let accelZ = forceZ / parameters.mass - gravity

        let dt = timeStep.delta
        let nextVz = store.state.velocity.z + accelZ * dt
        let nextZ = store.state.position.z + nextVz * dt

        guard nextVz.isFinite, nextZ.isFinite else {
            throw PlantError.nonFiniteState
        }

        let nextPosition = SIMD3<Double>(0.0, 0.0, nextZ)
        let nextVelocity = SIMD3<Double>(0.0, 0.0, nextVz)
        let nextOrientation = simd_quatd(angle: 0.0, axis: SIMD3<Double>(0, 0, 1))
        let nextAngular = SIMD3<Double>(repeating: 0.0)

        store.state = ReferenceQuadrotorState(
            uncheckedPosition: nextPosition,
            uncheckedVelocity: nextVelocity,
            uncheckedOrientation: nextOrientation,
            uncheckedAngularVelocity: nextAngular
        )
    }

    public func snapshot() -> PlantStateSnapshot {
        let root = RigidBodySnapshot(
            id: "root",
            position: Axis3(x: store.state.position.x, y: store.state.position.y, z: store.state.position.z),
            velocity: Axis3(x: store.state.velocity.x, y: store.state.velocity.y, z: store.state.velocity.z),
            orientation: QuaternionSnapshot(orientation: store.state.orientation),
            angularVelocity: Axis3(
                x: store.state.angularVelocity.x,
                y: store.state.angularVelocity.y,
                z: store.state.angularVelocity.z
            )
        )
        return PlantStateSnapshot(root: root)
    }

    public func safetyTrace() -> SafetyTrace {
        SafetyTrace(root: snapshot().root)
    }
}
