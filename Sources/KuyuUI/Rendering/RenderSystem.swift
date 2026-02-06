import Foundation
import RealityKit
import KuyuCore

public struct RenderSystem: Sendable {
    public func sceneState(for log: SimulationLog, time: Double) -> SceneState? {
        guard !log.events.isEmpty else { return nil }
        let dt = log.timeStep.delta
        let index = max(0, min(log.events.count - 1, Int(round(time / dt)) - 1))
        let event = log.events[index]
        let root = event.plantState.root
        let body = BodySceneState(
            id: root.id,
            position: root.position,
            velocity: root.velocity,
            orientation: root.orientation,
            angularVelocity: root.angularVelocity
        )
        return SceneState(time: event.time.time, bodies: [body])
    }

    public func loadEntity(info: RenderAssetInfo) async throws -> Entity {
        switch info.format {
        case .usdz, .usdc, .glb, .gltf, .obj:
            return try await MainActor.run {
                try ModelEntity.loadModel(contentsOf: info.url)
            }
        }
    }
}
