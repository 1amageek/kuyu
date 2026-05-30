import Foundation
import RealityKit
import KuyuCore
import KuyuPhysics

public struct RenderSystem: Sendable {
    public func sceneState(for log: SimulationLog, time: Double) -> SceneState? {
        guard !log.events.isEmpty else { return nil }
        let dt = log.timeStep.delta
        let index = max(0, min(log.events.count - 1, Int(round(time / dt)) - 1))
        let event = log.events[index]
        return SceneState(
            time: event.time.time,
            bodies: sceneBodies(from: event.plantState),
            scalars: event.plantState.scalars
        )
    }

    public func loadEntity(info: RenderAssetInfo) async throws -> Entity {
        (try await loadRobotEntity(info: info)).entity
    }

    func loadRobotEntity(info: RenderAssetInfo) async throws -> RenderedRobotEntity {
        switch info.format {
        case .urdf:
            let model = try URDFKinematicParser().parse(url: info.url)
            return try await MainActor.run {
                try URDFRealityEntityFactory().makeEntity(
                    model: model,
                    sourceURL: info.url,
                    scale: info.scale
                )
            }
        case .stl:
            return try await MainActor.run {
                RenderedRobotEntity(
                    entity: try STLMeshEntityFactory().makeEntity(url: info.url, scale: info.scale),
                    jointBindings: []
                )
            }
        case .usdz, .usdc, .glb, .gltf, .obj:
            return try await MainActor.run {
                let entity = try ModelEntity.loadModel(contentsOf: info.url)
                if let scale = info.scale {
                    entity.scale = [Float(scale.x), Float(scale.y), Float(scale.z)]
                }
                return RenderedRobotEntity(entity: entity, jointBindings: [])
            }
        }
    }

    private func sceneBodies(from plantState: PlantStateSnapshot) -> [BodySceneState] {
        ([plantState.root] + plantState.bodies).map { body in
            BodySceneState(
                id: body.id,
                position: body.position,
                velocity: body.velocity,
                orientation: body.orientation,
                angularVelocity: body.angularVelocity
            )
        }
    }
}
