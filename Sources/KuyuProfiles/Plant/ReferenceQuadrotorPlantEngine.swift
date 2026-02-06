import simd
import KuyuCore

public struct ReferenceQuadrotorPlantEngine: PlantEngine {
    public enum PlantError: Error, Equatable {
        case nonFiniteState
    }

    public var parameters: ReferenceQuadrotorParameters
    public var mixer: ReferenceQuadrotorMixer
    public var store: ReferenceQuadrotorWorldStore
    public let timeStep: TimeStep
    public let environment: WorldEnvironment

    public init(
        parameters: ReferenceQuadrotorParameters,
        mixer: ReferenceQuadrotorMixer,
        store: ReferenceQuadrotorWorldStore,
        timeStep: TimeStep,
        environment: WorldEnvironment = .standard
    ) {
        self.parameters = parameters
        self.mixer = mixer
        self.store = store
        self.timeStep = timeStep
        self.environment = environment
    }

    public mutating func integrate(time: WorldTime) throws {
        let mix = mixer.mix(thrusts: store.motorThrusts)
        var bodyForce = mix.forceBody
        var bodyTorque = mix.torqueBody
        var worldForce = store.disturbances.forceWorld
        let gravity = environment.effectiveGravity(defaultGravity: parameters.gravity)

        if environment.usage.useAtmosphere {
            let density = environment.airDensity()
            let ratio = density / WorldEnvironment.seaLevelDensity
            bodyForce *= ratio
            bodyTorque *= ratio
        }

        bodyTorque += store.disturbances.torqueBody

        if environment.usage.useWind || environment.usage.useAtmosphere {
            let windVelocity = environment.usage.useWind ? environment.windVelocityWorld.simd : SIMD3<Double>(repeating: 0)
            let airVelocity = store.state.velocity - windVelocity
            let speed = simd_length(airVelocity)

            if environment.usage.useAtmosphere {
                let density = environment.airDensity()
                let aero = parameters.aerodynamics

                if speed > 0, aero.dragCoefficient > 0, aero.referenceArea > 0 {
                    let dragMagnitude = 0.5 * density * aero.dragCoefficient * aero.referenceArea * speed * speed
                    let drag = -dragMagnitude * (airVelocity / speed)
                    worldForce += drag
                }

                if aero.liftCoefficient > 0, aero.referenceArea > 0 {
                    let airVelocityBody = store.state.orientation.inverse.act(airVelocity)
                    let bodySpeed = simd_length(airVelocityBody)
                    if bodySpeed > 0 {
                        let vHat = airVelocityBody / bodySpeed
                        let bodyUp = SIMD3<Double>(0, 0, 1)
                        let liftPlane = simd_cross(vHat, simd_cross(bodyUp, vHat))
                        let liftPlaneMag = simd_length(liftPlane)
                        if liftPlaneMag > 0 {
                            let liftMagnitude = 0.5 * density * aero.liftCoefficient * aero.referenceArea * bodySpeed * bodySpeed
                            let liftBody = liftPlane / liftPlaneMag * liftMagnitude
                            worldForce += store.state.orientation.act(liftBody)
                        }
                    }
                }

                if aero.bodyVolume > 0 {
                    let gravityWorld = SIMD3<Double>(0, 0, -gravity)
                    let buoyancy = -gravityWorld * (density * aero.bodyVolume)
                    worldForce += buoyancy
                }

                if aero.angularDrag.x > 0 || aero.angularDrag.y > 0 || aero.angularDrag.z > 0 {
                    let omega = store.state.angularVelocity
                    let damping = SIMD3<Double>(
                        aero.angularDrag.x * omega.x,
                        aero.angularDrag.y * omega.y,
                        aero.angularDrag.z * omega.z
                    )
                    bodyTorque -= damping
                }
            }
        }

        let input = ReferenceQuadrotorInput(
            bodyForce: bodyForce,
            bodyTorque: bodyTorque,
            worldForce: worldForce
        )

        let next = ReferenceQuadrotorDynamics.integrateRK4(
            state: store.state,
            input: input,
            parameters: parameters,
            gravity: gravity,
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
