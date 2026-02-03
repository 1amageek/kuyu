import Foundation
import RealityKit
import KuyuCore

struct RenderSystem {
    func sceneState(for log: SimulationLog, time: Double) -> SceneState? {
        guard !log.events.isEmpty else { return nil }
        let dt = log.timeStep.delta
        let index = max(0, min(log.events.count - 1, Int(round(time / dt)) - 1))
        let event = log.events[index]
        let robot = RobotSceneState(
            id: "robot-0",
            position: event.stateSnapshot.position,
            velocity: event.stateSnapshot.velocity,
            orientation: event.stateSnapshot.orientation,
            angularVelocity: event.stateSnapshot.angularVelocity
        )
        return SceneState(time: event.time.time, robots: [robot])
    }

    func loadEntity(info: RenderAssetInfo) async throws -> Entity {
        switch info.format {
        case .usdz, .usdc, .glb, .gltf, .obj:
            return try await MainActor.run {
                try ModelEntity.loadModel(contentsOf: info.url)
            }
        }
    }
}
